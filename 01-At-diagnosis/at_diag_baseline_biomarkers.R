
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

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "01/06/2024")

analysis = cprd$analysis("at_diag")


############################################################################################

# Define biomarkers
## Keep HbA1c separate as processed differently
## If you add biomarker to the end of this list, code should run fine to incorporate new biomarker, as long as you delete final 'baseline_biomarkers' table

biomarkers <- c("weight", "height", "bmi", "hdl", "triglyceride", "creatinine_blood", "ldl", "alt", "ast", "totalcholesterol", "dbp", "sbp", "acr", "fastingglucose")


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
## Remove those with invalid dates (before DOB or after LCD/deregistration)
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
    filter(obsdate>=min_dob & obsdate<=gp_end_date) %>%
    
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
  filter(obsdate>=min_dob & obsdate<=gp_end_date & year(obsdate)>=1990) %>%
    
  select(patid, date=obsdate, testvalue) %>%
    
  analysis$cached("clean_hba1c_medcodes", indexes=c("patid", "date", "testvalue"))


# Make eGFR table from creatinine readings and add to list of biomarkers
## Use DOBs produced in all_diabetes_cohort script to calculate age (uses yob, mob and also earliest medcode in yob to get dob, as per https://github.com/Exeter-Diabetes/CPRD-Codelists/blob/main/readme.md#general-notes-on-implementation)
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

## ACR two consectuive high readings

analysis = cprd$analysis("all")

acr_long <- acr_long %>% analysis$cached("patid_acr_long")

# Add gender column to ACR values
acr_long <- acr_long %>%
  left_join(
    diabetes_cohort %>% select(patid, gender),  
    by = "patid"
  )


# Two consecutive high ACR readings (men ≥2.5, women ≥3.5) and at least 90 days between readings
acr_confirmed_high <- acr_long %>%
  group_by(patid) %>%
  dbplyr::window_order(date) %>%
  # Sex specific ACR thresholds 
  mutate(
    threshold = case_when(
      gender == 1L ~ 2.5,   
      gender == 2L ~ 3.5,   
      TRUE         ~ 3.0 # if gender is missing use > 3    
    ),
    acr_high   = testvalue > threshold,
    prev_high  = lag(acr_high),
    prev_date  = lag(date),
    gap_days   = datediff(date, prev_date)         
  ) %>%
  # two consecutive highs and at least 90 days apart
  filter(acr_high & prev_high & gap_days >= 90) %>%
  ungroup() %>%
  select(
    patid,
    gender, threshold,
    first_high_date       = prev_date,           
    confirm_date_acr_high = date, # second consecutive test as confirmation date
    gap_days
  ) %>%
  distinct() 

analysis = cprd$analysis("at_diag")

# Join ACR readings with index dates
acr_idx <- acr_confirmed_high %>%
  inner_join(baseline_biomarkers %>% select(patid), by = "patid") %>%
  inner_join(index_dates, by = "patid") %>%
  select(patid, index_date, confirm_date_acr_high) 

# Create pre and post index date flags
acr_flags <- acr_idx %>%
  group_by(patid) %>%
  summarise(
    preacr_confirmed_earliest =
      min(if_else(confirm_date_acr_high <= index_date, confirm_date_acr_high, as.Date(NA))),
    preacr_confirmed_latest =
      max(if_else(confirm_date_acr_high <= index_date, confirm_date_acr_high, as.Date(NA))),
    postacr_confirmed_earliest =
      min(if_else(confirm_date_acr_high >  index_date, confirm_date_acr_high, as.Date(NA))),
    .groups = "drop"
  ) %>%
  mutate(
    preacr_confirmed  = as.integer(!is.na(preacr_confirmed_earliest)),
    postacr_confirmed = as.integer(!is.na(postacr_confirmed_earliest))
  )

# Join ACR confirmation flags to baseline biomarkers
baseline_biomarkers <- baseline_biomarkers %>%
  left_join(
    acr_flags %>%
      select(
        patid,
        preacr_confirmed,
        preacr_confirmed_earliest,
        preacr_confirmed_latest,
        postacr_confirmed,
        postacr_confirmed_earliest
      ),
    by = "patid"
  ) %>%
  mutate(
    preacr_confirmed  = coalesce(preacr_confirmed, 0L),
    postacr_confirmed = coalesce(postacr_confirmed, 0L)
  )





### Add in 40% decline in eGFR outcome: both based on single measurement and where confirmed by a second measurement at least 28 days later
### Join drug start dates with all longitudinal eGFR measurements, and only keep later eGFR measurements which are <=60% of the baseline value
### Checked and those with null eGFR do get dropped

analysis = cprd$analysis("all")

egfr_long <- egfr_long %>% analysis$cached("patid_clean_egfr_medcodes")

analysis = cprd$analysis("at_diag")

post_egfr_40_dates <- baseline_biomarkers %>%
  select(patid, index_date, preegfr) %>%
  filter(!is.na(preegfr)) %>%
  left_join(egfr_long, by = "patid") %>%
  filter(datediff(date, index_date) > 0,
         testvalue <= 0.6 * preegfr) %>%
  rename(egfr_40_date = date)

# eGFR 40% decline confirmation: any later eGFR (≥ 28 days after first low) also ≤ 60% of baseline
post_egfr40_decline_confirmed <- post_egfr_40_dates %>%
  select(patid, index_date, preegfr, egfr_40_date) %>%
  inner_join(egfr_long, by = "patid") %>%
  filter(datediff(date, egfr_40_date) >= 28,
         testvalue <= 0.6 * preegfr) %>%
  group_by(patid, index_date) %>%
  summarise(
    postegfr_40_decline_confirmed_earliest = min(date, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(postegfr_40_decline_confirmed = 1L) %>%
  analysis$cached("postegfr_40_decline_confirmed", indexes=c("patid"))

## confirmed 50% decline in eGFR
post_egfr_50_dates <- baseline_biomarkers %>%
  select(patid, index_date, preegfr) %>%
  filter(!is.na(preegfr)) %>%
  left_join(egfr_long, by = "patid") %>%
  filter(datediff(date, index_date) > 0,
         testvalue <= 0.5 * preegfr) %>%
  rename(egfr_50_date = date)

# eGFR 50% decline confirmation: any later eGFR (≥ 28 days after first low) also ≤ 50% of baseline
post_egfr50_decline_confirmed <- post_egfr_50_dates %>%
  select(patid, index_date, preegfr, egfr_50_date) %>%
  inner_join(egfr_long, by = "patid") %>%
  filter(datediff(date, egfr_50_date) >= 28,
         testvalue <= 0.5 * preegfr) %>%
  group_by(patid, index_date) %>%
  summarise(
    postegfr_50_decline_confirmed_earliest = min(date, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(postegfr_50_decline_confirmed = 1L)%>%
  analysis$cached("postegfr_50_decline_confirmed", indexes=c("patid"))



# Join eGFR 40% and 50% decline to baseline biomarkers
baseline_biomarkers <- baseline_biomarkers %>%
  left_join(post_egfr40_decline_confirmed, by = c("patid","index_date")) %>%
  left_join(post_egfr50_decline_confirmed, by = c("patid","index_date")) %>%
  mutate(
    postegfr_40_decline_confirmed = coalesce(postegfr_40_decline_confirmed, 0L),
    postegfr_50_decline_confirmed = coalesce(postegfr_50_decline_confirmed, 0L)
  )

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



# 42.1% missing BMI, mean BMI = 32.3
# Extend prebmi window - if prebmi is missing take BMI value one year after diagnosis or up to 5 years before diagnosis
bmi_fill <- clean_bmi_medcodes %>%
  inner_join(index_dates, by = "patid") %>%
  mutate(
    date_diff = datediff(date, index_date),
    priority = case_when(
      date_diff >= 0   & date_diff <= 365    ~ 1L,  # within 1 year after index
      date_diff <  0   & date_diff >= -5*365 ~ 2L,  # within 5 years before index
      TRUE                                   ~ 3L
    ),
    abs_date_diff = abs(date_diff)
  ) %>%
  # keep only within 1y post or 5y pre
  filter(priority < 3L) %>%
  group_by(patid) %>%
  slice_min(order_by = priority, with_ties = TRUE) %>%
  slice_min(order_by = abs_date_diff, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  rename(
    bmi_best      = testvalue,
    bmi_best_date = date
  ) %>%
  select(patid, bmi_best, bmi_best_date)

baseline_biomarkers <- baseline_biomarkers %>%
  left_join(bmi_fill, by = "patid") %>%
  mutate(
    prebmi = if_else(is.na(prebmi), bmi_best, prebmi)
  )

# % missing BMI after extending window = 14%, mean BMI = 31.8



## Join HbA1c to main table

baseline_biomarkers <- baseline_biomarkers %>%
  left_join(baseline_hba1c, by="patid") %>% 
  analysis$cached("baseline_biomarkers", unique_indexes="patid")

