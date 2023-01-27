
# Extracts dates for smoking code occurrences in GP records

# Merges with drug start and stop dates

# Defines smoking status at drug start dates according to both our algorithm, and QRISK2 algorithm (both described here: https://github.com/drkgyoung/Exeter_Diabetes_codelists#smoking)

# Both use same medcodes, but 'smoking' has our categories and 'qrisk_smoking' has QRISK2 categories


############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

analysis = cprd$analysis("mm")


############################################################################################

# Pull out all raw code instances and cache with 'all_patid' prefix

analysis = cprd$analysis("all_patid")

## Check codelists are identical
codes$smoking %>% count()          #194
codes$qrisk2_smoking %>% count()   #194
codes$smoking %>% inner_join(codes$qrisk2_smoking) %>% count()  #194


raw_smoking_medcodes <- cprd$tables$observation %>%
  inner_join(codes$smoking, by="medcodeid") %>%
  inner_join(codes$qrisk2_smoking, by="medcodeid") %>%
  analysis$cached("raw_smoking_medcodes", indexes=c("patid", "obsdate"))


############################################################################################

# Clean: remove if before DOB or after lcd/deregistration/death, and re-cache
## Remove duplicates for patid, date, 2 x categories and testvalue
## Keep testvalue, numunitid and medcodeid - need for QRISK2

clean_smoking_medcodes <- raw_smoking_medcodes %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(obsdate>=min_dob & obsdate<=gp_ons_end_date) %>%
  select(patid, date=obsdate, medcodeid, smoking_cat, qrisk2_smoking_cat, testvalue, numunitid) %>%
  distinct() %>%
  analysis$cached("clean_smoking_medcodes", indexes=c("patid", "date", "smoking_cat", "qrisk2_smoking_cat"))


############################################################################################

# Find smoking status according to both algorithms at drug start dates

# Get drug start dates
analysis = cprd$analysis("mm")
drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")


# Join with smoking codes on patid and retain codes before drug start date or up to 7 days after
predrug_smoking_codes <- drug_start_stop %>%
  select(patid, dstartdate, drugclass, druginstance) %>%
  inner_join(clean_smoking_medcodes, by="patid") %>%
  filter(datediff(date, dstartdate)<=7) %>%
  analysis$cached("predrug_smoking_merge", indexes=c("patid", "dstartdate", "drugclass", "smoking_cat", "qrisk2_smoking_cat"))


# Find smoking status at drug start date according to our algorithm

## Find if ever previously an active smoker
smoker_ever <- predrug_smoking_codes %>%
  filter(smoking_cat=="Active smoker") %>%
  distinct(patid, dstartdate, drugclass) %>%
  mutate(smoked_ever_flag=1L)

## Find most recent code (ignore testvalue) - only keep those with 1 type of category recorded on most recent date
most_recent_code <- predrug_smoking_codes %>%
  
  distinct(patid, dstartdate, drugclass, date, smoking_cat) %>%
  
  group_by(patid, dstartdate, drugclass) %>%
  filter(date==max(date, na.rm=TRUE)) %>%
  filter(n()==1) %>%
  ungroup() %>%
  
  select(patid, dstartdate, drugclass, most_recent_code=smoking_cat)

## Find next recorded code for those with multiple categories on most recent date
next_most_recent_code <- predrug_smoking_codes %>%
  
  distinct(patid, dstartdate, drugclass, date, smoking_cat) %>%
  
  group_by(patid, dstartdate, drugclass) %>%
  filter(date!=max(date, na.rm=TRUE)) %>%
  filter(date==max(date, na.rm=TRUE)) %>%
  filter(n()==1) %>%
  ungroup() %>%
  
  select(patid, dstartdate, drugclass, next_most_recent_code=smoking_cat)
  
## Pull together
smoking_cat <- drug_start_stop %>%
  select(patid, dstartdate, drugclass) %>%
  left_join(smoker_ever, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(most_recent_code, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(next_most_recent_code, by=c("patid", "dstartdate", "drugclass")) %>%
  mutate(most_recent_code=coalesce(most_recent_code, next_most_recent_code),
         smoking_cat=ifelse(most_recent_code=="Non-smoker" & !is.na(smoked_ever_flag) & smoked_ever_flag==1, "Ex-smoker", most_recent_code)) %>%
  select(-c(most_recent_code, next_most_recent_code, smoked_ever_flag)) %>%
  analysis$cached("smoking_interim_1", indexes=c("patid", "dstartdate", "drugclass"))


# Work out smoking status from QRISK2 algorithm

## Only keep codes within 5 years, keep those on most recent date, and convert to QRISK2 categories using testvalues (only use testvalues if valid numunitid)
qrisk2_smoking_cat <- predrug_smoking_codes %>%
  
  filter(datediff(dstartdate, date) <= 1826) %>%
  
  group_by(patid, dstartdate, drugclass) %>%
  filter(date==max(date, na.rm=TRUE)) %>%
  ungroup() %>%
  
  mutate(qrisk2_smoking=ifelse(is.na(testvalue) | qrisk2_smoking_cat==1 | medcodeid==1780396011 | (!is.na(numunitid) & numunitid!=39 & numunitid!=118 & numunitid!=247 & numunitid!=98 & numunitid!=120 & numunitid!=237 & numunitid!=478 & numunitid!=1496 & numunitid!=1394 & numunitid!=1202 & numunitid!=38), qrisk2_smoking_cat,
                               ifelse(testvalue<10, 2L,
                                      ifelse(testvalue<20, 3L, 4L))))

## If more than 1 category on most recent day, use minimum
qrisk2_smoking_cat <- qrisk2_smoking_cat %>%
  group_by(patid, dstartdate, drugclass) %>%
  summarise(qrisk2_smoking_cat=min(qrisk2_smoking, na.rm=TRUE)) %>%
  ungroup() %>%
  analysis$cached("smoking_interim_2", indexes=c("patid", "dstartdate", "drugclass"))


# Join results of our algorithm and QRISK2 algorithm and add uncoded version of QRISK2 category

smoking <- drug_start_stop %>%
  select(patid, dstartdate, drugclass, druginstance) %>%
  left_join(smoking_cat, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(qrisk2_smoking_cat, by=c("patid", "dstartdate", "drugclass")) %>%
  mutate(qrisk2_smoking_cat_uncoded=case_when(qrisk2_smoking_cat==0 ~ "Non-smoker",
                                              qrisk2_smoking_cat==1 ~ "Ex-smoker",
                                              qrisk2_smoking_cat==2 ~ "Light smoker",
                                              qrisk2_smoking_cat==3 ~ "Moderate smoker",
                                              qrisk2_smoking_cat==4 ~ "Heavy smoker")) %>%
  analysis$cached("smoking", indexes=c("patid", "dstartdate", "drugclass"))
  


