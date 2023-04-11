
# Extracts dates for smoking code occurrences in GP records

# Merges with index dates

# Defines smoking status at index dates according to both our algorithm, and QRISK2 algorithm (both described here: https://github.com/Exeter-Diabetes/CPRD-Codelists#smoking)

# Both use same medcodes, but 'smoking' has our categories and 'qrisk_smoking' has QRISK2 categories


############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

cohort_prefix <- ""
# e.g. "mm" for treatment response (MASTERMIND) cohort

analysis = cprd$analysis(cohort_prefix)


############################################################################################

# Pull out all raw code instances and cache with 'all_patid' prefix

analysis = cprd$analysis("all_patid")

## Check codelists are identical
codes$smoking %>% count()          #194
codes$qrisk2_smoking %>% count()   #194
codes$smoking %>% inner_join(codes$qrisk2_smoking, by="medcodeid") %>% count()  #194


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

# Find smoking status according to both algorithms at index dates

## Get index dates

analysis = cprd$analysis(cohort_prefix)

index_dates <- index_dates %>% analysis$cached("index_dates")


## Join with smoking codes on patid and retain codes before index date or up to 7 days after
pre_index_date_smoking_codes <- index_dates %>%
  inner_join(clean_smoking_medcodes, by="patid") %>%
  filter(datediff(date, index_date)<=7) %>%
  analysis$cached("pre_index_date_smoking_merge", indexes=c("patid", "index_date", "smoking_cat", "qrisk2_smoking_cat"))



## Find smoking status at index date according to our algorithm

### Find if ever previously an active smoker
smoker_ever <- pre_index_date_smoking_codes %>%
  filter(smoking_cat=="Active smoker") %>%
  distinct(patid, index_date) %>%
  mutate(smoked_ever_flag=1L)

### Find most recent code (ignore testvalue)
#### If both non- and ex-smoker, use ex-smoker
#### If conflicting categories (non- and active- / ex- and active-), treat as missing
most_recent_code <- pre_index_date_smoking_codes %>%
  distinct(patid, index_date, date, smoking_cat) %>%
  group_by(patid, index_date) %>%
  filter(date==max(date, na.rm=TRUE)) %>%
  ungroup() %>%
  select(-date) %>%
  mutate(fill=TRUE) %>%
  pivot_wider(id_cols=c(patid, index_date), names_from=smoking_cat, values_from=fill, values_fill=list(fill=FALSE)) %>%
  mutate(smoking_cat=ifelse(`Active smoker`==1 & `Non-smoker`==0 & `Ex-smoker`==0, "Active smoker",
                            ifelse(`Active smoker`==0 & `Ex-smoker`==1, "Ex-smoker",
                                   ifelse(`Active smoker`==0 & `Ex-smoker`==0 & `Non-smoker`==1, "Non-smoker", NA)))) %>%
  select(patid, index_date, most_recent_code=smoking_cat) %>%
  analysis$cached("smoking_interim_1", indexes=c("patid", "index_date"))
    
### Find next recorded code (to use for those with conflicting categories on most recent date)
next_most_recent_code <- pre_index_date_smoking_codes %>%
  distinct(patid, index_date, date, smoking_cat) %>%
  group_by(patid, index_date) %>%
  filter(date!=max(date, na.rm=TRUE)) %>%
  filter(date==max(date, na.rm=TRUE)) %>%
  ungroup() %>%
  select(-date) %>%
  mutate(fill=TRUE) %>%
  pivot_wider(id_cols=c(patid, index_date), names_from=smoking_cat, values_from=fill, values_fill=list(fill=FALSE)) %>%
  mutate(smoking_cat=ifelse(`Active smoker`==1 & `Non-smoker`==0 & `Ex-smoker`==0, "Active smoker",
                            ifelse(`Active smoker`==0 & `Ex-smoker`==1, "Ex-smoker",
                                   ifelse(`Active smoker`==0 & `Ex-smoker`==0 & `Non-smoker`==1, "Non-smoker", NA)))) %>%
  select(patid, index_date, next_most_recent_code=smoking_cat) %>%
  analysis$cached("smoking_interim_2", indexes=c("patid", "index_date"))

### Pull together
smoking_cat <- index_dates %>%
  left_join(smoker_ever, by=c("patid", "index_date")) %>%
  left_join(most_recent_code, by=c("patid", "index_date")) %>%
  left_join(next_most_recent_code, by=c("patid", "index_date")) %>%
  mutate(most_recent_code=coalesce(most_recent_code, next_most_recent_code),
         smoking_cat=ifelse(most_recent_code=="Non-smoker" & !is.na(smoked_ever_flag) & smoked_ever_flag==1, "Ex-smoker", most_recent_code)) %>%
  select(-c(most_recent_code, next_most_recent_code, smoked_ever_flag)) %>%
  analysis$cached("smoking_interim_3", indexes=c("patid", "index_date"))



# Work out smoking status from QRISK2 algorithm

## Only keep codes within 5 years, keep those on most recent date, and convert to QRISK2 categories using testvalues (only use testvalues if valid numunitid)
qrisk2_smoking_cat <- pre_index_date_smoking_codes %>%
  filter(datediff(index_date, date) <= 1826) %>%
  group_by(patid, index_date) %>%
  filter(date==max(date, na.rm=TRUE)) %>%
  ungroup() %>%
  mutate(qrisk2_smoking=ifelse(is.na(testvalue) | qrisk2_smoking_cat==1 | medcodeid==1780396011 | (!is.na(numunitid) & numunitid!=39 & numunitid!=118 & numunitid!=247 & numunitid!=98 & numunitid!=120 & numunitid!=237 & numunitid!=478 & numunitid!=1496 & numunitid!=1394 & numunitid!=1202 & numunitid!=38), qrisk2_smoking_cat,
                               ifelse(testvalue<10, 2L,
                                      ifelse(testvalue<20, 3L, 4L)))) %>%
  analysis$cached("smoking_interim_4", indexes=c("patid", "index_date"))

## If both non- and ex-smoker, use ex-smoker
## If conflicting categories (non- and active- / ex- and active-), use minimum
qrisk2_smoking_cat <- qrisk2_smoking_cat %>%
  mutate(fill=TRUE, qrisk2_smoking_cat=paste0("cat_", qrisk2_smoking)) %>%
  distinct(patid, index_date, qrisk2_smoking_cat, fill) %>%
  pivot_wider(id_cols=c(patid, index_date), names_from=qrisk2_smoking_cat, values_from=fill, values_fill=list(fill=FALSE)) %>%
  mutate(qrisk2_smoking_cat=ifelse(cat_1==1, 1L,
                                   ifelse(cat_0==1 & cat_1==0, 0L,
                                          ifelse(cat_0==0 & cat_1==0 & cat_2==1, 2L,
                                                 ifelse(cat_0==0 & cat_1==0 & cat_2==0 & cat_3==1, 3L,
                                                        ifelse(cat_0==0 & cat_1==0 & cat_2==0 & cat_3==0 & cat_4==1, 4L, NA)))))) %>%
  select(patid, index_date, qrisk2_smoking_cat) %>%
  analysis$cached("smoking_interim_5", indexes=c("patid", "index_date"))



# Join results of our algorithm and QRISK2 algorithm and add uncoded version of QRISK2 category

smoking <- index_dates %>%
  left_join(smoking_cat, by=c("patid", "index_date")) %>%
  left_join(qrisk2_smoking_cat, by=c("patid", "index_date")) %>%
  mutate(qrisk2_smoking_cat_uncoded=case_when(qrisk2_smoking_cat==0 ~ "Non-smoker",
                                              qrisk2_smoking_cat==1 ~ "Ex-smoker",
                                              qrisk2_smoking_cat==2 ~ "Light smoker",
                                              qrisk2_smoking_cat==3 ~ "Moderate smoker",
                                              qrisk2_smoking_cat==4 ~ "Heavy smoker")) %>%
  analysis$cached("smoking", indexes=c("patid", "index_date"))
  


