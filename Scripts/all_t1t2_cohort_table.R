
# Identify those in mixed T1/T2 cohort as per https://github.com/Exeter-Diabetes/CPRD-Codelists#diabetes-algorithms

# Add useful baseline features including diabetes diagnosis variables (date of diagnosis, type of diabetes) and ethnicity

# Uses other pre-made tables:
## validDateLookup has min_dob (earliest possible DOB), ons_death (date of death [dod] or date of death registration [dor] if dod missing from ONS death records, and gp_ons_end_date (earliest of last collection date from practice, deregistration, cprd_ddate and ons_death)
## patidsWithLinkage has patids of those with linkage to HES APC, IMD and ONS death records plus n_patid_hes (how many patids linked with 1 HES record)
## all_patid_ethnicity has ethnicity_5cat, ethnicity_16cat, and ethnicity_qrisk2 derived as per https://github.com/Exeter-Diabetes/CPRD-Codelists#ethnicity
## all_patid_townsend_score has tds_2011 derived as per https://github.com/Exeter-Diabetes/CPRD-Codelists#townsend-deprivation-scores 


############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

analysis = cprd$analysis("diagnosis_date")


############################################################################################

# Initial data quality checks

## Our download should not have included non-'acceptable' patients (see CPRD data specification for definition)
## It should have only included patients with registration start dates up to 10/2018 (as we used the October 2020 Aurum release, and only included patients with a diabetes medcode within registration and with at least 1 year of UTS data before and after)
## However, we have some non-acceptable patients and some patients registered in 2020 (none between 10/2018-08/2020, inclusive) - remove these people

acceptable_patids <- cprd$tables$patient %>%
  filter(acceptable==1 & year(regstartdate)!=2020) %>%
  select(patid)


############################################################################################

# T1T2 cohort definition

# Define T1T2 cohort (has diabetes QOF code with valid date, has no diabetes exclusion codes)
## QOF codelist uses Read codes from version 38 and SNOMED codes from version 44, which include all codes from previous versions. Codes for non-T1/T2 types of diabetes were removed, but these codes are also in the 'exclusion_diabetes' codelist anyway.

exclusion_patids <- cprd$tables$observation %>%
  semi_join(codes$exclusion_diabetes) %>%
  select(patid)

t1t2_ids <- cprd$tables$observation %>%
  inner_join(codes$qof_diabetes) %>%
  inner_join(cprd$tables$validDateLookup) %>%
  filter(obsdate>=min_dob & obsdate<=gp_ons_end_date) %>%
  semi_join(acceptable_patids) %>%
  anti_join(exclusion_patids)%>%
  select(patid) %>%
  distinct() %>%
  analysis$cached("t1t2_ids", unique_indexes="patid")


############################################################################################

# Diagnosis dates

# Earliest of: diabetes medcode (excluding obstype==4 (family history)), HbA1c >=48mmol/mol, OHA script, insulin script (all - valid dates only)

## If Type 2 (determined later in this script), ignore any diabetes medcodes in year of birth - use next code/HbA1c/script
## If Type 2 and have high HbA1c or OHA/insulin script in year of birth, will exclude later
## Similarly, if Type 2 and ONLY have diabetes medcodes in year of birth (and no high HbA1cs or OHA/insulin scripts later), will exclude later

## All diabetes medcodes, OHA scripts and insulin scripts also needed for defining diabetes type - so cache these
## Have also cached HbA1c as needed for later analysis
## Haven't filtered on patids in T1T2 cohort as doesn't make much difference to numbers

analysis = cprd$analysis("all")

## All diabetes medcodes (need for diagnosis date (cleaned) and Type 1 vs Type 2 (raw))
raw_diabetes_medcodes <- cprd$tables$observation %>%
  inner_join(codes$all_diabetes) %>%
  analysis$cached("patid_raw_diabetes_medcodes", indexes=c("patid", "obsdate", "all_diabetes_cat"))


## All HbA1cs - could clean on import but do separately for now
raw_hba1c <- cprd$tables$observation %>%
  inner_join(codes$hba1c) %>%
  analysis$cached("patid_raw_hba1c_medcodes", indexes=c("patid", "obsdate", "testvalue", "numunitid"))

clean_hba1c <- raw_hba1c %>%
  filter(year(obsdate)>=1990) %>%
  mutate(testvalue=ifelse(testvalue<=20, ((testvalue-2.152)/0.09148), testvalue)) %>%
  clean_biomarker_units(testvalue, "hba1c") %>%
  clean_biomarker_values(numunitid, "hba1c") %>%
  group_by(patid, obsdate) %>%
  summarise(testvalue=mean(testvalue, na.rm=TRUE)) %>%
  ungroup() %>%
  inner_join(cprd$tables$validDateLookup) %>%
  filter(obsdate>=min_dob & obsdate<=gp_ons_end_date) %>%
  select(patid, date=obsdate, testvalue) %>%
  analysis$cached("patid_clean_hba1c_medcodes", indexes=c("patid", "date", "testvalue"))


## All OHA scripts (need for diagnosis date (cleaned) and definition (cleaned))
clean_oha <- cprd$tables$drugIssue %>%
  inner_join(cprd$tables$ohaLookup) %>%
  inner_join(cprd$tables$validDateLookup) %>%
  filter(issuedate>=min_dob & issuedate<=gp_ons_end_date) %>%
  select(patid, date=issuedate, dosageid, quantity, quantunitid, duration, INS, TZD, SU, DPP4, MFN, GLP1, Glinide, Acarbose, SGLT2) %>%
  analysis$cached("patid_clean_oha_prodcodes", indexes=c("patid", "date", "INS", "TZD", "SU", "DPP4", "MFN", "GLP1", "Glinide", "Acarbose", "SGLT2"))


## All insulin scripts (need for diagnosis date (cleaned) and definition (cleaned))
clean_insulin <- cprd$tables$drugIssue %>%
  inner_join(codes$insulin) %>%
  inner_join(cprd$tables$validDateLookup) %>%
  filter(issuedate>=min_dob & issuedate<=gp_ons_end_date) %>%
  select(patid, date=issuedate, dosageid, quantity, quantunitid, duration) %>%
  analysis$cached("patid_clean_insulin_prodcodes", indexes=c("patid", "date"))



# Cleaning required for diagnosis dates
## If construct query this way (finding earliest date from each of the diagnosis codes, HbA1cs and prescriptions, and then combining, rather than combining all dates and then finding earliest date, doesn't give error about disk space)

analysis = cprd$analysis("diagnosis_date")

## Earliest clean (i.e. with valid date) non-family history diabetes medcode
first_diagnosis_dm_code <- raw_diabetes_medcodes %>%
  filter(obstypeid!=4) %>%
  inner_join(cprd$tables$validDateLookup) %>%
  filter(obsdate>=min_dob & obsdate<=gp_ons_end_date) %>%
  group_by(patid) %>%
  summarise(date=min(obsdate, na.rm=TRUE)) %>%
  analysis$cached("first_diagnosis_dm_code", unique_index="patid")

## Earliest clean (i.e. with valid date) non-family history diabetes medcode excluding those in year of birth
first_diagnosis_dm_code_post_yob <- raw_diabetes_medcodes %>%
  filter(obstypeid!=4) %>%
  inner_join(cprd$tables$validDateLookup) %>%
  filter(year(obsdate)>year(min_dob) & obsdate<=gp_ons_end_date) %>%
  group_by(patid) %>%
  summarise(date=min(obsdate, na.rm=TRUE)) %>%
  analysis$cached("first_diagnosis_dm_code_post_yob", unique_index="patid")


## Earliest (clean) HbA1c >=48 mmol/mol
first_high_hba1c <- clean_hba1c_clean_units %>%
  filter(testvalue>47.5) %>%
  group_by(patid) %>%
  summarise(date=min(date, na.rm=TRUE)) %>%
  analysis$cached("first_high_hba1c", unique_index="patid")


## Earliest (clean) OHA script
first_oha <- clean_oha %>%
  group_by(patid) %>%
  summarise(date=min(date, na.rm=TRUE)) %>%
  analysis$cached("first_oha", unique_index="patid")


## Earliest (clean) insulin script
first_insulin <- clean_insulin %>%
  group_by(patid) %>%
  summarise(date=min(date, na.rm=TRUE)) %>%
  analysis$cached("first_insulin", unique_index="patid")


# Calculate possible diagnosis dates (overall earliest of code/HbA1c/script, and earliest excluding codes in year of birth)
dm_diag_dates <- t1t2_ids %>%
  left_join((first_diagnosis_dm_code %>% rename(dm_diag_dmcodedate=date)), by="patid") %>%
  left_join((first_diagnosis_dm_code_post_yob %>% rename(dm_diag_dmcodedate_post_yob=date)), by="patid") %>%
  left_join((first_high_hba1c %>% rename(dm_diag_hba1cdate=date)), by="patid") %>%
  left_join((first_oha %>% rename(dm_diag_ohadate=date)), by="patid") %>%
  left_join((first_insulin %>% rename(dm_diag_insdate=date)), by="patid") %>%
  
  mutate(dm_diag_date_all = pmin(ifelse(is.na(dm_diag_dmcodedate), as.Date("2050-01-01"), dm_diag_dmcodedate),
                                 ifelse(is.na(dm_diag_hba1cdate), as.Date("2050-01-01"), dm_diag_hba1cdate),
                                 ifelse(is.na(dm_diag_ohadate), as.Date("2050-01-01"), dm_diag_ohadate),
                                 ifelse(is.na(dm_diag_insdate), as.Date("2050-01-01"), dm_diag_insdate), na.rm=TRUE),
         
         dm_diag_date_all_post_yob = pmin(ifelse(is.na(dm_diag_dmcodedate_post_yob), as.Date("2050-01-01"), dm_diag_dmcodedate_post_yob),
                                         ifelse(is.na(dm_diag_hba1cdate), as.Date("2050-01-01"), dm_diag_hba1cdate),
                                         ifelse(is.na(dm_diag_ohadate), as.Date("2050-01-01"), dm_diag_ohadate),
                                         ifelse(is.na(dm_diag_insdate), as.Date("2050-01-01"), dm_diag_insdate), na.rm=TRUE)) %>%
  
  analysis$cached("dm_diag_dates", unique_indexes="patid", indexes=c("dm_diag_date_all", "dm_diag_date_all_post_yob"))
         

############################################################################################

# Define diabetes type: 1 or 2

# Make queries for variables requires

## Whether or not have valid insulin prescription
has_insulin <- clean_insulin %>%
  select(patid) %>%
  distinct() %>%
  mutate(has_insulin=1L) %>%
  analysis$cached("has_insulin", unique_indexes="patid")


## Type 1-specific code count (any date)
type1_code_count <- raw_diabetes_medcodes %>%
  filter(all_diabetes_cat=="Type 1") %>%
  group_by(patid) %>%
  summarise(type1_code_count=n()) %>%
  analysis$cached("type1_code_count", unique_indexes="patid")


## Type 2-specific code count (any date)
type2_code_count <-
  raw_diabetes_medcodes %>%
  filter(all_diabetes_cat=="Type 2") %>%
  group_by(patid) %>%
  summarise(type2_code_count=n()) %>%
  analysis$cached("type2_code_count", unique_indexes="patid")


## Age of diagnosis
### First need to estimate DOB: earliest of any medcode in Observation table (besides those before mob/yob), or use the 15/mob/yob if mob where provided, or 01/07/yob if only yob provided

dob <- cprd$tables$observation %>%
  inner_join(cprd$tables$validDateLookup) %>%
  filter(obsdate>=min_dob) %>%
  group_by(patid) %>%
  summarise(earliest_medcode=min(obsdate, na.rm=TRUE)) %>%
  analysis$cached("earliest_medcode", unique_indexes="patid")

### Check count
dob %>% count()
### 1,481,294 - has everyone

### No-one has missing dob or earliest_medcode so pmin (runs as 'LEAST' in MySQL) works
dob <- dob %>%
  inner_join(cprd$tables$patient) %>%
  mutate(dob=as.Date(ifelse(is.na(mob), paste0(yob,"-07-01"), paste0(yob, "-",mob,"-15")))) %>%
  mutate(dob=pmin(dob, earliest_medcode, na.rm=TRUE)) %>%
  select(patid, dob, mob, yob, regstartdate) %>%
  analysis$cached("dob", unique_indexes="patid")

### Calculate from dob and diagnosis date
### Also add in whether diagnosis date < regstartdate as will need this for time to insulin
dm_diag_age <- dm_diag_dates %>%
 left_join(dob) %>%
  mutate(dm_diag_age_all=(datediff(dm_diag_date_all, dob))/365.25,
         dm_diag_age_all_post_yob=(datediff(dm_diag_date_all_post_yob, dob))/365.25,
         dm_diag_before_reg=dm_diag_date_all<regstartdate,
         dm_diag_before_reg_post_yob=dm_diag_date_all_post_yob<regstartdate) %>%
  select(patid, dob, mob, yob, regstartdate, starts_with("dm_diag")) %>%
  analysis$cached("dm_diag_age", unique_indexes="patid", indexes=c("dm_diag_date_all", "dm_diag_age_all"))


## Whether first insulin script within 1 year of diagnosis
### Included even if prescription is before registration start
time_to_insulin <- clean_insulin %>%
  group_by(patid) %>%
  summarise(first_insulin=min(date, na.rm=TRUE)) %>%
  ungroup() %>%
  inner_join(dm_diag_dates) %>%
  mutate(ins_in_1_year=ifelse(datediff(first_insulin, dm_diag_date_all)/365.25<=1, 1L, NA),
         ins_in_1_year_post_yob=ifelse(datediff(first_insulin, dm_diag_date_all_post_yob)/365.25<=1, 1L, NA)) %>%
  select(patid, ins_in_1_year, ins_in_1_year_post_yob) %>%
  analysis$cached("time_to_insulin", unique_indexes="patid")


## Current OHA status (whether have prescription for OHA in last 6 months of records)
current_oha <- clean_oha %>%
  group_by(patid) %>%
  summarise(latest_oha=max(date, na.rm=TRUE)) %>%
  ungroup() %>%
  inner_join(cprd$tables$validDateLookup) %>%
  filter((datediff(gp_ons_end_date, latest_oha))/365.25<=0.5) %>%
  mutate(current_oha=1L) %>%
  select(patid, current_oha) %>%
  analysis$cached("current_oha", unique_indexes="patid")


# Calculate diabetes type when include and exclude diabetes medcodes in year of birth (yob)

diabetes_type_prelim <- t1t2_ids %>%
  left_join(has_insulin ,by="patid") %>%
  left_join(type1_code_count, by="patid") %>%
  left_join(type2_code_count, by="patid") %>%
  inner_join(dm_diag_age, by="patid") %>%
  left_join(time_to_insulin, by="patid") %>%
  left_join(current_oha, by="patid") %>%
  replace_na(list(has_insulin=0L, type1_code_count=0L, type2_code_count=0L, ins_in_1_year=0L, ins_in_1_year_post_yob=0L, current_oha=0L)) %>%
  mutate(diabetes_type=ifelse(
    (
      (has_insulin==1 & type1_code_count!=0 & type2_code_count!=0 & type1_code_count>=(2*type2_code_count)) |
        (has_insulin==1 & type1_code_count!=0 & type2_code_count==0) |
        (has_insulin==1 & type1_code_count==0 & type2_code_count==0 & dm_diag_age_all<35 & ins_in_1_year==1) |
        (has_insulin==1 & type1_code_count==0 & type2_code_count==0 & dm_diag_age_all<35 & dm_diag_before_reg==1 & current_oha==0)
    ),
    "type 1","type 2"),
    
    diabetes_type_post_yob=ifelse(
      (
        (has_insulin==1 & type1_code_count!=0 & type2_code_count!=0 & type1_code_count>=(2*type2_code_count)) |
          (has_insulin==1 & type1_code_count!=0 & type2_code_count==0) |
          (has_insulin==1 & type1_code_count==0 & type2_code_count==0 & dm_diag_age_all_post_yob<35 & ins_in_1_year_post_yob==1) |
          (has_insulin==1 & type1_code_count==0 & type2_code_count==0 & dm_diag_age_all_post_yob<35 & dm_diag_before_reg_post_yob==1 & current_oha==0)
      ),
      "type 1","type 2")) %>%
  
  analysis$cached("diabetes_type_prelim", unique_indexes="patid")


# Check those that have a different type of diabetes depending on whether include medcodes in year of birth or not
check <- collect(diabetes_type_prelim %>%
  filter(diabetes_type!=diabetes_type_post_yob))
## 10 people: 9 are Type 1 if include codes in year of birth, and Type 2 otherwise, 1 is Type 2 if include codes in year of birth, and Type 1 otherwise as affects time to insulin
## Class these people as unclassifiable

# Check those with T2D who still have diagnosis date in year of birth due to having script or high HbA1c in year of birth
check <- collect(diabetes_type_prelim %>%
                   filter(diabetes_type=="type 2" & diabetes_type_post_yob=="type 2" & year(dm_diag_date_all_post_yob)==yob))
## 4 people: 3 with OHA in yob, 1 with high HbA1c
## Exclude these people

# Check those with T2D who only have diabetes medcodes in year of birth and no later codes/HbA1cs/scripts
check <- collect(diabetes_type_prelim %>%
                   filter(diabetes_type=="type 2" & diabetes_type_post_yob=="type 2" & is.na(dm_diag_date_all_post_yob)))
# 0 people



# Exclude Type 2s with diagnosis date in year of birth
# Finalise diabetes type and date of diagnosis - recode dm_diag_dmcodedate, dm_diag_date_all, dm_diag_age_all, dm_diag_before_reg and ins_in_1_year so include/exclude diabetes medcodes in year of birth depending on diabetes type

diabetes_type_final <- diabetes_type_prelim %>%
  
  filter(!(diabetes_type=="type 2" & diabetes_type_post_yob=="type 2" & year(dm_diag_date_all_post_yob)==yob)) %>%
  
  mutate(diabetes_type=ifelse(diabetes_type!=diabetes_type_post_yob, "unclassifiable", diabetes_type),
         
         dm_diag_dmcodedate=ifelse(diabetes_type=="type 2", dm_diag_dmcodedate_post_yob, dm_diag_dmcodedate),
         
         dm_diag_date_all=ifelse(diabetes_type=="type 2", dm_diag_date_all_post_yob, dm_diag_date_all),
         
         dm_diag_age_all=ifelse(diabetes_type=="type 2", dm_diag_age_all_post_yob, dm_diag_age_all),
         
         dm_diag_before_reg=ifelse(diabetes_type=="type 2", dm_diag_before_reg_post_yob, dm_diag_before_reg),
         
         ins_in_1_year=ifelse(diabetes_type=="type 2", ins_in_1_year_post_yob, ins_in_1_year)) %>%
  
  select(-c(ends_with("post_yob"))) %>%

  analysis$cached("diabetes_type_final", unique_indexes="patid")


############################################################################################

# Add in other variables and cache
## Whether diagnosis date needs flag (if within 90 days of start of registration), and what type of code diagnosis is based on
## Also add in gender, registration end, practice ID, and cprd_ddate from patient table
## Also add in last collection date for practice, death date from ONS records, and whether has HES data from patidsWithLinkage lookup and derive/keep: regstartdate, gp_record_end (earliest of last collection date from practice, deregistration and 31/10/2020 (latest date in records)), death_date (earliest of 'cprddeathdate' (derived by CPRD) and ONS death date), and with_hes (patients with HES linkage and n_patid_hes<=20)
## Also add in ethnicity from all_patid_ethnicity table derived as per: https://github.com/Exeter-Diabetes/CPRD-Codelists#ethnicity
## Also add in IMD and Townsend Deprivation Score from all_patid_townsend_score derived as per: https://github.com/Exeter-Diabetes/CPRD-Codelists#townsend-deprivation-scores 

analysis = cprd$analysis("all")

ethnicity <- ethnicity %>% analysis$cached("patid_ethnicity")
imd_townsend <- imd_townsend %>% analysis$cached("patid_townsend_score")

t1t2_cohort <- diabetes_type_final %>%
  mutate(dm_diag_codetype = ifelse(is.na(dm_diag_date_all), NA,
                                   ifelse(!is.na(dm_diag_dmcodedate) & dm_diag_dmcodedate==dm_diag_date_all, 1L,
                                          ifelse(!is.na(dm_diag_hba1cdate) & dm_diag_hba1cdate==dm_diag_date_all, 2L,
                                                 ifelse(!is.na(dm_diag_ohadate) & dm_diag_ohadate==dm_diag_date_all, 3L, 4L)))),
         
         dm_diag_flag=(dm_diag_date_all>=regstartdate & datediff(dm_diag_date_all,regstartdate)<91)) %>%
  
  left_join((cprd$tables$patient %>% select(patid, gender, regenddate, pracid, cprd_ddate)), by="patid") %>%
  left_join((cprd$tables$practice %>% select(pracid, lcd, region)), by="pracid") %>%
  left_join((cprd$tables$validDateLookup %>% select(patid, ons_death)), by="patid") %>%
  left_join((cprd$tables$patidsWithLinkage %>% select(patid, n_patid_hes)), by="patid") %>%
  
  mutate(gp_record_end=pmin(if_else(is.na(lcd), as.Date("2020-10-31"), lcd),
                            if_else(is.na(regenddate), as.Date("2020-10-31"), regenddate),
                            as.Date("2020-10-31"), na.rm=TRUE),
         
         death_date=pmin(if_else(is.na(cprd_ddate), as.Date("2050-01-01"), cprd_ddate),
                         if_else(is.na(ons_death), as.Date("2050-01-01"), ons_death), na.rm=TRUE),
         death_date=if_else(death_date==as.Date("2050-01-01"), as.Date(NA), death_date),
         
         with_hes=ifelse(!is.na(n_patid_hes) & n_patid_hes<=20, 1L, 0L)) %>%
  
  left_join(ethnicity, by="patid") %>%
  left_join(imd_townsend, by="patid") %>%
  
  select(patid, gender, dob, pracid, prac_region=region, ethnicity_5cat, ethnicity_16cat, ethnicity_qrisk2, imd2015_10, tds_2011, has_insulin, type1_code_count, type2_code_count, dm_diag_dmcodedate, dm_diag_hba1cdate, dm_diag_ohadate, dm_diag_insdate, dm_diag_date_all, dm_diag_codetype, dm_diag_flag, dm_diag_age_all, dm_diag_before_reg, ins_in_1_year, current_oha, diabetes_type, regstartdate, gp_record_end, death_date, with_hes) %>% 
  
  analysis$cached("t1t2_cohort", unique_indexes="patid",indexes=c("gender", "dob", "dm_diag_date_all", "dm_diag_age_all", "diabetes_type"))
