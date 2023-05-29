
# Extracts and cleans all biomarker values (and creates eGFR readings from creatinine if not already done in all_patid_ckd_stages script)

# Merges with index dates (diagnosis dates)

# Finds biomarker values at baseline (index date): -2 years to +7 days relative to index date for all except:
## HbA1c: -6 months to +7 days
## Height: mean of all values >= index date

# NB: creatinine_blood and eGFR tables may already have been cached as part of all_patid_ckd_stages script
## and HbA1c tables may already have been cached as part of all_diabetes_cohort script


############################################################################################

# Setup
library(tidyverse)
library(aurum)
library(EHRBiomarkr)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

analysis = cprd$analysis("at_diag")


############################################################################################

# Define biomarkers
## Keep HbA1c separate as processed differently
## If you add biomarker to the end of this list, code should run fine to incorporate new biomarker, as long as you delete final 'baseline_biomarkers' table

biomarkers <- c("weight", "height", "bmi", "hdl", "triglyceride", "creatinine_blood", "ldl", "alt", "ast", "totalcholesterol", "dbp", "sbp", "acr")


############################################################################################

# Pull out all raw biomarker values and cache

analysis = cprd$analysis("all_patid")

for (i in biomarkers) {
  
  print(i)
 
  raw_tablename <- paste0("raw_", i, "_medcodes")

  data <- cprd$tables$observation %>%
    inner_join(codes[[i]], by="medcodeid") %>%
    analysis$cached(raw_tablename, indexes=c("patid", "obsdate", "testvalue", "numunitid"))
  
  assign(raw_tablename, data)

}


# HbA1c

raw_hba1c_medcodes <- cprd$tables$observation %>%
    inner_join(codes$hba1c, by="medcodeid") %>%
    analysis$cached("raw_hba1c_medcodes", indexes=c("patid", "obsdate", "testvalue", "numunitid"))


############################################################################################

# Clean biomarkers:
## Only keep those within acceptable value limits
## Only keep those with valid unit codes (numunitid)
## If multiple values on the same day, take mean
## Remove those with invalid dates (before DOB or after LCD/death/deregistration)
### HbA1c only: remove if <1990 and assume in % and convert to mmol/mol if <=20 (https://github.com/Exeter-Diabetes/CPRD-Codelists#hba1c)


analysis = cprd$analysis("all_patid")


for (i in biomarkers) {
  
  print(i)
  
  raw_tablename <- paste0("raw_", i, "_medcodes")
  clean_tablename <- paste0("clean_", i, "_medcodes")
  
  data <- get(raw_tablename) %>%
    clean_biomarker_values(testvalue, i) %>%
    clean_biomarker_units(numunitid, i) %>%
    
    group_by(patid,obsdate) %>%
    summarise(testvalue=mean(testvalue, na.rm=TRUE)) %>%
    ungroup() %>%
    
    inner_join(cprd$tables$validDateLookup, by="patid") %>%
    filter(obsdate>=min_dob & obsdate<=gp_ons_end_date) %>%
    
    select(patid, date=obsdate, testvalue) %>%
    
    analysis$cached(clean_tablename, indexes=c("patid", "date", "testvalue"))
  
  assign(clean_tablename, data)
    
}


# HbA1c

clean_hba1c_medcodes <- raw_hba1c_medcodes %>%
  
  mutate(testvalue=ifelse(testvalue<=20,((testvalue-2.152)/0.09148),testvalue)) %>%
  
  clean_biomarker_values(testvalue, "hba1c") %>%
  clean_biomarker_units(numunitid, "hba1c") %>%
    
  group_by(patid,obsdate) %>%
  summarise(testvalue=mean(testvalue, na.rm=TRUE)) %>%
  ungroup() %>%
    
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(obsdate>=min_dob & obsdate<=gp_ons_end_date & year(obsdate)>=1990) %>%
    
  select(patid, date=obsdate, testvalue) %>%
    
  analysis$cached("clean_hba1c_medcodes", indexes=c("patid", "date", "testvalue"))


# Make eGFR table from creatinine readings and add to list of biomarkers
## Use DOBs produced in all_t1t2_cohort script to calculate age (uses yob, mob and also earliest medcode in yob to get dob, as per https://github.com/Exeter-Diabetes/CPRD-Codelists/blob/main/readme.md#general-notes-on-implementation)
## Also need gender from Patient table for eGFR

analysis = cprd$analysis("diabetes_cohort")

dob <- dob %>% analysis$cached("dob")

analysis = cprd$analysis("all_patid")

clean_egfr_medcodes <- clean_creatinine_blood_medcodes %>%
  
  inner_join((dob %>% select(patid, dob)), by="patid") %>%
  inner_join((cprd$tables$patient %>% select(patid, gender)), by="patid") %>%
  mutate(age_at_creat=(datediff(date, dob))/365.25,
         sex=ifelse(gender==1, "male", ifelse(gender==2, "female", NA))) %>%
  select(-c(dob, gender)) %>%
  
  ckd_epi_2021_egfr(creatinine=testvalue, sex=sex, age_at_creatinine=age_at_creat) %>%
  select(-c(testvalue, sex, age_at_creat)) %>%
  
  rename(testvalue=ckd_epi_2021_egfr) %>%
  filter(!is.na(testvalue)) %>%
  analysis$cached("clean_egfr_medcodes", indexes=c("patid", "date", "testvalue"))

biomarkers <- c("egfr", biomarkers)


############################################################################################

# Combine each biomarker with index dates

## Get index dates (diagnosis dates)

analysis = cprd$analysis("all")

diabetes_cohort <- diabetes_cohort %>% analysis$cached("diabetes_cohort")

index_dates <- diabetes_cohort %>%
  filter(!is.na(dm_diag_date)) %>%
  select(patid, index_date=dm_diag_date)


## Merge with biomarkers and calculate date difference between biomarker and index date

analysis = cprd$analysis("at_diag")

for (i in biomarkers) {
  
  print(i)
  
  clean_tablename <- paste0("clean_", i, "_medcodes")
  index_date_merge_tablename <- paste0("full_", i, "_index_date_merge")
  
  data <- get(clean_tablename) %>%
    inner_join(index_dates, by="patid") %>%
    mutate(datediff=datediff(date, index_date))
  
  assign(index_date_merge_tablename, data)
  
}


# HbA1c

full_hba1c_index_date_merge <- clean_hba1c_medcodes %>%
  inner_join(index_dates, by="patid") %>%
  mutate(datediff=datediff(date, index_date))


############################################################################################

# Find baseline values
## Within period defined above (-2 years to +7 days for all except HbA1c and height)
## Then use closest date to index date
## May be multiple values; use minimum test result, except for eGFR - use maximum
## Can get duplicates where person has identical results on the same day/days equidistant from the index date - choose first row when ordered by datediff

baseline_biomarkers <- index_dates


## For all except HbA1c and height: between 2 years prior and 7 days after index date

biomarkers_no_height <- setdiff(biomarkers, "height")

for (i in biomarkers_no_height) {
  
  print(i)
  
  index_date_merge_tablename <- paste0("full_", i, "_index_date_merge")
  interim_baseline_biomarker_table <- paste0("baseline_biomarkers_interim_", i)
  pre_biomarker_variable <- paste0("pre", i)
  pre_biomarker_date_variable <- paste0("pre", i, "date")
  pre_biomarker_datediff_variable <- paste0("pre", i, "datediff")
  
  
  data <- get(index_date_merge_tablename) %>%
    filter(datediff<=7 & datediff>=-730) %>%
    
    group_by(patid) %>%
    
    mutate(min_timediff=min(abs(datediff), na.rm=TRUE)) %>%
    filter(abs(datediff)==min_timediff) %>%
    
    mutate(pre_biomarker=ifelse(i=="egfr", max(testvalue, na.rm=TRUE), min(testvalue, na.rm=TRUE))) %>%
    filter(pre_biomarker==testvalue) %>%
    
    dbplyr::window_order(datediff) %>%
    filter(row_number()==1) %>%
    
    ungroup() %>%
    
    relocate(pre_biomarker, .after=patid) %>%
    relocate(date, .after=pre_biomarker) %>%
    relocate(datediff, .after=date) %>%
    
    rename({{pre_biomarker_variable}}:=pre_biomarker,
           {{pre_biomarker_date_variable}}:=date,
           {{pre_biomarker_datediff_variable}}:=datediff) %>%
    
    select(-c(testvalue, min_timediff))
  
  
  baseline_biomarkers <- baseline_biomarkers %>%
    left_join((data %>% select(-index_date)), by="patid") %>%
    analysis$cached(interim_baseline_biomarker_table, unique_indexes="patid")
    
}


## Height - only keep readings at/post-index date, and find mean

baseline_height <- full_height_index_date_merge %>%
  filter(datediff>=0) %>%
  group_by(patid) %>%
  summarise(height=mean(testvalue, na.rm=TRUE)) %>%
  ungroup()

baseline_biomarkers <- baseline_biomarkers %>%
  left_join(baseline_height, by="patid")

  
## HbA1c: only between 6 months prior and 7 days after index date
### NB: in treatment response cohort, baseline HbA1c set to missing if occurs before previous treatment change

baseline_hba1c <- full_hba1c_index_date_merge %>%

  filter(datediff<=7 & datediff>=-183) %>%
  
  group_by(patid) %>%
    
  mutate(min_timediff=min(abs(datediff), na.rm=TRUE)) %>%
  filter(abs(datediff)==min_timediff) %>%
    
  mutate(prehba1c=min(testvalue, na.rm=TRUE)) %>%
  filter(prehba1c==testvalue) %>%
    
  dbplyr::window_order(datediff) %>%
  filter(row_number()==1) %>%
  
  ungroup() %>%
  
  relocate(prehba1c, .after=patid) %>%
  relocate(date, .after=prehba1c) %>%
  relocate(datediff, .after=date) %>%
    
  rename(prehba1cdate=date,
         prehba1cdatediff=datediff) %>%
    
  select(-c(testvalue, min_timediff, index_date))


## Join HbA1c to main table

baseline_biomarkers <- baseline_biomarkers %>%
  left_join(baseline_hba1c, by="patid") %>% 
  analysis$cached("baseline_biomarkers", unique_indexes="patid")

