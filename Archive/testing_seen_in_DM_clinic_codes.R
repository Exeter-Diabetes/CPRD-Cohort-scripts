# DePICtion work suggests 'seen in diabetes clinic' medcodes (medcodeid 285223014) are not specific to those with diabetes
# Test effect of removal of these codes on diabetes diagnosis dates

############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("diabetes_cohort")

############################################################################################

# Diagnosis dates

# Earliest of: diabetes medcode (including diabetes exclusion codes; excluding obstype==4 [family history]), HbA1c >=47.5mmol/mol, OHA script, insulin script (all - valid dates only)

## If Type 2 (determined later in this script), ignore any diabetes medcodes in year of birth - use next code/HbA1c/script
## If Type 2 and have high HbA1c or OHA/insulin script in year of birth, will exclude later
## Similarly, if Type 2 and ONLY have diabetes medcodes in year of birth (and no high HbA1cs or OHA/insulin scripts later), will exclude later

## All diabetes medcodes, OHA scripts and insulin scripts also needed for defining diabetes type - so cache these
## Have also cached HbA1c as needed for later analysis

analysis = cprd$analysis("all_patid")


## All diabetes medcodes (only includes Type 1/Type 2 and unspecified; need for diagnosis date (cleaned) and for defining Type 1 vs Type 2 (raw))
raw_diabetes_medcodes <- cprd$tables$observation %>%
  inner_join(codes$all_diabetes, by="medcodeid") %>%
  analysis$cached("raw_diabetes_medcodes", indexes=c("patid", "obsdate", "all_diabetes_cat"))

## All diabetes exclusion medcodes (need for diagnosis date (cleaned))
raw_exclusion_diabetes_medcodes <- cprd$tables$observation %>%
  inner_join(codes$exclusion_diabetes, by="medcodeid") %>%
  analysis$cached("raw_exclusion_diabetes_medcodes", indexes=c("patid", "obsdate", "exclusion_diabetes_cat"))


## All HbA1cs - could clean on import but do separately for now
### Remove if <1990 and assume in % and convert to mmol/mol if <=20 (https://github.com/Exeter-Diabetes/CPRD-Codelists#hba1c)
raw_hba1c <- cprd$tables$observation %>%
  inner_join(codes$hba1c, by="medcodeid") %>%
  analysis$cached("raw_hba1c_medcodes", indexes=c("patid", "obsdate", "testvalue", "numunitid"))

clean_hba1c <- raw_hba1c %>%
  filter(year(obsdate)>=1990) %>%
  mutate(testvalue=ifelse(testvalue<=20, ((testvalue-2.152)/0.09148), testvalue)) %>%
  clean_biomarker_units(testvalue, "hba1c") %>%
  clean_biomarker_values(numunitid, "hba1c") %>%
  group_by(patid, obsdate) %>%
  summarise(testvalue=mean(testvalue, na.rm=TRUE)) %>%
  ungroup() %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(obsdate>=min_dob & obsdate<=gp_ons_end_date) %>%
  select(patid, date=obsdate, testvalue) %>%
  analysis$cached("clean_hba1c_medcodes", indexes=c("patid", "date", "testvalue"))


## All OHA scripts (need for diagnosis date (cleaned) and definition (cleaned))
clean_oha <- cprd$tables$drugIssue %>%
  inner_join(cprd$tables$ohaLookup, by="prodcodeid") %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(issuedate>=min_dob & issuedate<=gp_ons_end_date) %>%
  select(patid, date=issuedate, dosageid, quantity, quantunitid, duration, INS, TZD, SU, DPP4, MFN, GLP1, Glinide, Acarbose, SGLT2) %>%
  analysis$cached("clean_oha_prodcodes", indexes=c("patid", "date", "INS", "TZD", "SU", "DPP4", "MFN", "GLP1", "Glinide", "Acarbose", "SGLT2"))


## All insulin scripts (need for diagnosis date (cleaned) and definition (cleaned))
clean_insulin <- cprd$tables$drugIssue %>%
  inner_join(codes$insulin, by="prodcodeid") %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(issuedate>=min_dob & issuedate<=gp_ons_end_date) %>%
  select(patid, date=issuedate, dosageid, quantity, quantunitid, duration) %>%
  analysis$cached("clean_insulin_prodcodes", indexes=c("patid", "date"))



# Cleaning required for diagnosis dates
## If construct query this way (finding earliest date from each of the diagnosis codes, HbA1cs and prescriptions, and then combining, rather than combining all dates and then finding earliest date, doesn't give error about disk space)

analysis = cprd$analysis("diabetes_cohort")

## Earliest clean (i.e. with valid date) non-family history diabetes medcode (including diabetes exclusion codes)
first_diagnosis_dm_code_no_seendmcln_codes <- raw_diabetes_medcodes %>%
  filter(medcodeid!=285223014) %>%
  select(patid, obsdate, obstypeid) %>%
  union_all((raw_exclusion_diabetes_medcodes %>% select(patid, obsdate, obstypeid))) %>%
  filter(obstypeid!=4) %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(obsdate>=min_dob & obsdate<=gp_ons_end_date) %>%
  group_by(patid) %>%
  summarise(dm_diag_dmcodedate=min(obsdate, na.rm=TRUE)) %>%
  analysis$cached("first_diagnosis_dm_code_no_seendmcln_codes", unique_index="patid")

## Earliest clean (i.e. with valid date) non-family history diabetes medcode (including diabetes exclusion codes) excluding those in year of birth
first_diagnosis_dm_code_post_yob_no_sdc_codes <- raw_diabetes_medcodes %>%
  filter(medcodeid!=285223014) %>%
  select(patid, obsdate, obstypeid) %>%
  union_all((raw_exclusion_diabetes_medcodes %>% select(patid, obsdate, obstypeid))) %>%
  filter(obstypeid!=4) %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(year(obsdate)>year(min_dob) & obsdate<=gp_ons_end_date) %>%
  group_by(patid) %>%
  summarise(dm_diag_dmcodedate_post_yob=min(obsdate, na.rm=TRUE)) %>%
  analysis$cached("first_diagnosis_dm_code_post_yob_no_sdc_codes", unique_index="patid")


## Earliest (clean) HbA1c >=48 mmol/mol
first_high_hba1c <- clean_hba1c %>%
  filter(testvalue>47.5) %>%
  group_by(patid) %>%
  summarise(dm_diag_hba1cdate=min(date, na.rm=TRUE)) %>%
  analysis$cached("first_high_hba1c", unique_index="patid")


## Earliest (clean) OHA script
first_oha <- clean_oha %>%
  group_by(patid) %>%
  summarise(dm_diag_ohadate=min(date, na.rm=TRUE)) %>%
  analysis$cached("first_oha", unique_index="patid")


## Earliest (clean) insulin script
first_insulin <- clean_insulin %>%
  group_by(patid) %>%
  summarise(dm_diag_insdate=min(date, na.rm=TRUE)) %>%
  analysis$cached("first_insulin", unique_index="patid")


# Calculate possible diagnosis dates (overall earliest of code/HbA1c/script, and earliest excluding codes in year of birth)

diabetes_ids <- diabetes_ids %>% analysis$cached("ids")

dm_diag_dates_no_sdmc_codes <- diabetes_ids %>%
  left_join(first_diagnosis_dm_code_no_seendmcln_codes, by="patid") %>%
  left_join(first_diagnosis_dm_code_post_yob_no_sdc_codes, by="patid") %>%
  left_join(first_high_hba1c, by="patid") %>%
  left_join(first_oha, by="patid") %>%
  left_join(first_insulin, by="patid") %>%
  
  mutate(dm_diag_date_all = pmin(ifelse(is.na(dm_diag_dmcodedate), as.Date("2050-01-01"), dm_diag_dmcodedate),
                                 ifelse(is.na(dm_diag_hba1cdate), as.Date("2050-01-01"), dm_diag_hba1cdate),
                                 ifelse(is.na(dm_diag_ohadate), as.Date("2050-01-01"), dm_diag_ohadate),
                                 ifelse(is.na(dm_diag_insdate), as.Date("2050-01-01"), dm_diag_insdate), na.rm=TRUE),
         
         dm_diag_date_all_post_yob = pmin(ifelse(is.na(dm_diag_dmcodedate_post_yob), as.Date("2050-01-01"), dm_diag_dmcodedate_post_yob),
                                          ifelse(is.na(dm_diag_hba1cdate), as.Date("2050-01-01"), dm_diag_hba1cdate),
                                          ifelse(is.na(dm_diag_ohadate), as.Date("2050-01-01"), dm_diag_ohadate),
                                          ifelse(is.na(dm_diag_insdate), as.Date("2050-01-01"), dm_diag_insdate), na.rm=TRUE)) %>%
  
  analysis$cached("dm_diag_dates_no_sdmc_codes", unique_indexes="patid")


dm_diag_dates <- dm_diag_dates %>% analysis$cached("dm_diag_dates")

test <- dm_diag_dates_no_sdmc_codes %>%
  select(patid, dm_diag_date_all, dm_diag_date_all_post_yob) %>%
  inner_join((dm_diag_dates %>% select(patid, old_dm_diag_date_all=dm_diag_date_all, old_dm_diag_date_all_post_yob=dm_diag_date_all_post_yob)), by="patid")

test %>% count()
#1,138,193
test %>% filter(dm_diag_date_all!=old_dm_diag_date_all) %>% count()
#14,098
test %>% filter(dm_diag_date_all_post_yob!=old_dm_diag_date_all_post_yob) %>% count()
#13,841

test %>% filter(dm_diag_date_all!=old_dm_diag_date_all) %>% mutate(timediff=datediff(dm_diag_date_all, old_dm_diag_date_all)) %>% summarise(mean=mean(timediff, na.rm=TRUE))
#1628 days
