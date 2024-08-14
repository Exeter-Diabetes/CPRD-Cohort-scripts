
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

analysis = cprd$analysis("pedro_BP_183")


############################################################################################

# Pull out all raw code instances and cache with 'all_patid' prefix

analysis = cprd$analysis("all_patid")

# Clean: remove if before DOB or after lcd/deregistration/death, and re-cache
## Remove duplicates for patid, date, 2 x categories and testvalue
## Keep testvalue, numunitid and medcodeid - need for QRISK2

clean_smoking_medcodes <- clean_smoking_medcodes %>%
  analysis$cached("clean_smoking_medcodes", indexes=c("patid", "date", "smoking_cat", "qrisk2_smoking_cat"))


############################################################################################

# Find smoking status according to both algorithms at drug start dates

# Get drug start dates
analysis = cprd$analysis("pedro_BP_183")
drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")


# Join with smoking codes on patid and retain codes before drug start date or up to 7 days after
predrug_smoking_codes <- drug_start_stop %>%
  # select important variables
  select(patid, dstartdate, drugclass, druginstance) %>%
  # combine with clean smoking medcodes
  inner_join(clean_smoking_medcodes, by="patid") %>%
  # calculate difference between smoking code date and drug start date
  filter(datediff(date, dstartdate)<=7) %>%
  # cache this table
  analysis$cached("predrug_smoking_merge", indexes=c("patid", "dstartdate", "drugclass", "smoking_cat", "qrisk2_smoking_cat"))


# Find smoking status at drug start date according to our algorithm

## Find if ever previously an active smoker
smoker_ever <- predrug_smoking_codes %>%
  # filter only active smokers
  filter(smoking_cat=="Active smoker") %>%
  # keep only unique entries
  distinct(patid, dstartdate, drugclass) %>%
  # create variable
  mutate(smoked_ever_flag=1L)

## Find most recent code (ignore testvalue)
### If both non- and ex-smoker, use ex-smoker
### If conflicting categories (non- and active- / ex- and active-), treat as missing
most_recent_code <- predrug_smoking_codes %>%
  # keep only unique entries
  distinct(patid, dstartdate, drugclass, date, smoking_cat) %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # keep only those with latest date of smoking
  filter(date==max(date, na.rm=TRUE)) %>%
  # remove grouping
  ungroup() %>%
  # remove date
  select(-date) %>%
  # create variable
  mutate(fill=TRUE) %>%
  # pivot this table from long to wide
  pivot_wider(
    # column names to keep
    id_cols=c(patid, dstartdate, drugclass), 
    # column names to pivot
    names_from=smoking_cat, 
    # take value from this column
    values_from=fill, values_fill=list(fill=FALSE)) %>%
  # create variable
  mutate(smoking_cat=ifelse(`Active smoker`==1 & `Non-smoker`==0 & `Ex-smoker`==0, "Active smoker",
                            ifelse(`Active smoker`==0 & `Ex-smoker`==1, "Ex-smoker",
                                   ifelse(`Active smoker`==0 & `Ex-smoker`==0 & `Non-smoker`==1, "Non-smoker", NA)))) %>%
  # select important variable
  select(patid, dstartdate, drugclass, most_recent_code=smoking_cat) %>%
  # cache this table
  analysis$cached("smoking_interim_1", indexes=c("patid", "dstartdate", "drugclass"))

## Find next recorded code (to use for those with conflicting categories on most recent date)
next_most_recent_code <- predrug_smoking_codes %>%
  # keep only unique entries
  distinct(patid, dstartdate, drugclass, date, smoking_cat) %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # keep those which aren't the maximum
  filter(date!=max(date, na.rm=TRUE)) %>%
  filter(date==max(date, na.rm=TRUE)) %>%
  # remove grouping
  ungroup() %>%
  # remove column
  select(-date) %>%
  # create variable
  mutate(fill=TRUE) %>%
  # pivot this table from long to wide
  pivot_wider(
    # column names to keep
    id_cols=c(patid, dstartdate, drugclass), 
    # column names to pivot
    names_from=smoking_cat, 
    # take value from this column
    values_from=fill, values_fill=list(fill=FALSE)) %>%
  # create variable
  mutate(smoking_cat=ifelse(`Active smoker`==1 & `Non-smoker`==0 & `Ex-smoker`==0, "Active smoker",
                            ifelse(`Active smoker`==0 & `Ex-smoker`==1, "Ex-smoker",
                                   ifelse(`Active smoker`==0 & `Ex-smoker`==0 & `Non-smoker`==1, "Non-smoker", NA)))) %>%
  # select important variable
  select(patid, dstartdate, drugclass, next_most_recent_code=smoking_cat) %>%
  # cache this table
  analysis$cached("smoking_interim_2", indexes=c("patid", "dstartdate", "drugclass"))

## Pull together
smoking_cat <- drug_start_stop %>%
  # select important variables
  select(patid, dstartdate, drugclass) %>%
  # combine drug starts with smoking variables
  left_join(smoker_ever, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(most_recent_code, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(next_most_recent_code, by=c("patid", "dstartdate", "drugclass")) %>%
  # create variable
  mutate(most_recent_code=coalesce(most_recent_code, next_most_recent_code),
         smoking_cat=ifelse(most_recent_code=="Non-smoker" & !is.na(smoked_ever_flag) & smoked_ever_flag==1, "Ex-smoker", most_recent_code)) %>%
  # remove columns
  select(-c(most_recent_code, next_most_recent_code, smoked_ever_flag)) %>%
  # cache this table
  analysis$cached("smoking_interim_3", indexes=c("patid", "dstartdate", "drugclass"))



# Work out smoking status from QRISK2 algorithm

## Only keep codes within 5 years, keep those on most recent date, and convert to QRISK2 categories using testvalues (only use testvalues if valid numunitid)
qrisk2_smoking_cat <- predrug_smoking_codes %>%
  # keep values within 5 years
  filter(datediff(dstartdate, date) <= 1826) %>%
  # group by patid, drug start date, drug class
  group_by(patid, dstartdate, drugclass) %>%
  # keep latest date
  filter(date==max(date, na.rm=TRUE)) %>%
  # remove grouping
  ungroup() %>%
  # create variables
  mutate(qrisk2_smoking=ifelse(is.na(testvalue) | qrisk2_smoking_cat==1 | medcodeid==1780396011 | (!is.na(numunitid) & numunitid!=39 & numunitid!=118 & numunitid!=247 & numunitid!=98 & numunitid!=120 & numunitid!=237 & numunitid!=478 & numunitid!=1496 & numunitid!=1394 & numunitid!=1202 & numunitid!=38), qrisk2_smoking_cat,
                               ifelse(testvalue<10, 2L,
                                      ifelse(testvalue<20, 3L, 4L)))) %>%
  # cache this table
  analysis$cached("smoking_interim_4", indexes=c("patid", "dstartdate", "drugclass"))

## If both non- and ex-smoker, use ex-smoker
## If conflicting categories (non- and active- / ex- and active-), use minimum
qrisk2_smoking_cat <- qrisk2_smoking_cat %>%
  # create variable
  mutate(fill=TRUE, qrisk2_smoking_cat=paste0("cat_", qrisk2_smoking)) %>%
  # keep unique entries
  distinct(patid, dstartdate, drugclass, qrisk2_smoking_cat, fill) %>%
  # pivot this table from long to wide
  pivot_wider(
    # column names to keep
    id_cols=c(patid, dstartdate, drugclass), 
    # column names to pivot
    names_from=qrisk2_smoking_cat, 
    # take value from this column
    values_from=fill, values_fill=list(fill=FALSE)) %>%
  # create variable
  mutate(qrisk2_smoking_cat=ifelse(cat_1==1, 1L,
                                   ifelse(cat_0==1 & cat_1==0, 0L,
                                          ifelse(cat_0==0 & cat_1==0 & cat_2==1, 2L,
                                                 ifelse(cat_0==0 & cat_1==0 & cat_2==0 & cat_3==1, 3L,
                                                        ifelse(cat_0==0 & cat_1==0 & cat_2==0 & cat_3==0 & cat_4==1, 4L, NA)))))) %>%
  # select important columns
  select(patid, dstartdate, drugclass, qrisk2_smoking_cat) %>%
  # cache this table
  analysis$cached("smoking_interim_5", indexes=c("patid", "dstartdate", "drugclass"))



# Join results of our algorithm and QRISK2 algorithm and add uncoded version of QRISK2 category

smoking <- drug_start_stop %>%
  # select important columns
  select(patid, dstartdate, drugclass, druginstance) %>%
  # combine drug start drugs with smoking tables
  left_join(smoking_cat, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(qrisk2_smoking_cat, by=c("patid", "dstartdate", "drugclass")) %>%
  # create variable
  mutate(qrisk2_smoking_cat_uncoded=case_when(qrisk2_smoking_cat==0 ~ "Non-smoker",
                                              qrisk2_smoking_cat==1 ~ "Ex-smoker",
                                              qrisk2_smoking_cat==2 ~ "Light smoker",
                                              qrisk2_smoking_cat==3 ~ "Moderate smoker",
                                              qrisk2_smoking_cat==4 ~ "Heavy smoker")) %>%
  # cache this table
  analysis$cached("smoking", indexes=c("patid", "dstartdate", "drugclass"))





