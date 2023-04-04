
# Extracts and cleans all biomarker values (and creates eGFR readings from creatinine)

# Merges with drug start and stop dates plus timetochange, timeaddrem and multi_drug_start variables from mm_combo_start_stop (combination start and stop dates) table - these 3 variables needed for working out response biomarkers in script 3_mm_response_biomarkers

# Finds biomarker values at baseline: -2 years to +7 days relative to drug start for all except:
## HbA1c: -6 months to +7 days, and excludes any before timeprevcombo
## Height: mean of all values >= drug start

# NB: creatinine_blood and eGFR tables may already have been cached as part of all_patid_ckd_stages script


############################################################################################

# Setup
library(tidyverse)
library(aurum)
library(EHRBiomarkr)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

analysis = cprd$analysis("mm")


############################################################################################

# Define biomarkers
## Keep HbA1c separate as processed differently

biomarkers <- c("weight", "height", "bmi", "fastingglucose", "hdl", "triglyceride", "creatinine_blood", "ldl", "alt", "ast", "totalcholesterol", "dbp", "sbp", "acr", "albumin_blood", "bilirubin", "haematocrit", "haemoglobin", "pcr", "albumin_urine", "creatinine_urine")


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

# HbA1c table should already be present from all_t1t2_cohort script

raw_hba1c_medcodes <- cprd$tables$observation %>%
    inner_join(codes$hba1c, by="medcodeid") %>%
    analysis$cached("raw_hba1c_medcodes", indexes=c("patid", "obsdate", "testvalue", "numunitid"))


############################################################################################

# Clean biomarkers:
## Only keep those within acceptable value limits
## Only keep those with valid unit codes (numunitid)
## If multiple values on the same day, take mean
## Remove those with invalid dates (before DOB or after LCD/death/deregistration)

## Urine albumin and creatinine: can't determine acceptable value limits as huge range in urine depending on how concentrated it is
## Similarly, can't keep those with missing unit codes as might be mg/g (albumin) or mmol/umol (creatinine) and can't tell from value
## Urine albumin: 66% of readings have unit code 183=mg/L; keep these. Remainder are missing or <1%
## Urine creatinine: 85% of readings have unit codes 218=mmol/L and 8% 285=umol/L; keep these and convert umol/L to mmol/L. Rest are missing or <1%
## Combine to get ACR and then clean values

## Haematocrit only: convert all to proportion by dividing those >1 by 100
## Haemoglobin only: convert all to g/L (some in g/dL) by multiplying values <30 by 10
## HbA1c only: remove before 1990, and convert all values to mmol/mol
### NB: HbA1c table already present from all_t1t2_cohort script


analysis = cprd$analysis("all_patid")


for (i in biomarkers) {
  
  print(i)
  
  raw_tablename <- paste0("raw_", i, "_medcodes")
  clean_tablename <- paste0("clean_", i, "_medcodes")
  
  if (i=="haematocrit") {
    message("Converting haematocrit values to proportion out of 1")
    raw_data <- get(raw_tablename) %>%
      mutate(testvalue=ifelse(testvalue>1, testvalue/100, testvalue))
  }
  else if (i=="haemoglobin") {
    message("Converting haemoglobin values to g/L")
    raw_data <- get(raw_tablename) %>%
      mutate(testvalue=ifelse(testvalue<30, testvalue*10, testvalue))
  }
  else {
    raw_data <- get(raw_tablename)
  }
  
  
  if (i=="albumin_urine") {
    data <- raw_data %>%
      filter(numunitid==183)
  }
  else if (i=="creatinine_urine") {
    data <- raw_data %>%
      filter(numunitid==218 | numunitid==285) %>%
      mutate(testvalue=ifelse(numunitid==285, testvalue/1000, testvalue))
  }
  else {
    data <- raw_data %>%
      clean_biomarker_values(testvalue, i) %>%
      clean_biomarker_units(numunitid, i)
  }
  
  
  data <- data %>%
    
    group_by(patid,obsdate) %>%
    summarise(testvalue=mean(testvalue, na.rm=TRUE)) %>%
    ungroup() %>%
    
    inner_join(cprd$tables$validDateLookup, by="patid") %>%
    filter(obsdate>=min_dob & obsdate<=gp_ons_end_date) %>%
    
    select(patid, date=obsdate, testvalue) %>%
    
    analysis$cached(clean_tablename, indexes=c("patid", "date", "testvalue"))
  
  assign(clean_tablename, data)
    
}


# HbA1c table should already be present from all_t1t2_cohort script

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
## Also need gender for eGFR

analysis = cprd$analysis("diagnosis_date")

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


# Make ACR from separate urine albumin and urine creatinine measurements on the same day
# Then clean values

clean_acr_from_separate_medcodes <- clean_albumin_urine_medcodes %>%
  inner_join((clean_creatinine_urine_medcodes %>% select(patid, creat_date=date, creat_value=testvalue)), by="patid") %>%
  filter(date==creat_date) %>%
  mutate(new_testvalue=testvalue/creat_value) %>%
  select(patid, date, testvalue=new_testvalue) %>%
  clean_biomarker_values(testvalue, "acr") %>%
  analysis$cached("clean_acr_from_separate_medcodes", indexes=c("patid", "date", "testvalue"))

biomarkers <- setdiff(biomarkers, c("albumin_urine", "creatinine_urine"))
biomarkers <- c("acr_from_separate", biomarkers)


############################################################################################

# Combine each biomarker with start dates of all drug periods (not just first instances; with timetochange, timeaddrem and multi_drug_start added from mm_combo_start_stop table), and cache as separate tables

## Get drug start dates

analysis = cprd$analysis("mm")

drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")

combo_start_stop <- combo_start_stop %>% analysis$cached("combo_start_stop")

drug_start_dates <- drug_start_stop %>%
  left_join((combo_start_stop %>% select(patid, dcstartdate, timetochange, timetoaddrem, multi_drug_start)), by=c("patid","dstartdate"="dcstartdate")) %>%
  select(patid, dstartdate, drugclass, druginstance, timetochange, timetoaddrem, multi_drug_start)


## Merge with biomarkers and calculate date difference between biomarker and drug start date

for (i in biomarkers) {
  
  print(i)
  
  clean_tablename <- paste0("clean_", i, "_medcodes")
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  
  data <- get(clean_tablename) %>%
    inner_join(drug_start_dates, by="patid") %>%
    mutate(drugdatediff=datediff(date, dstartdate)) %>%
    
    analysis$cached(drug_merge_tablename, indexes=c("patid", "dstartdate", "drugclass"))
  
  assign(drug_merge_tablename, data)
  
}


# HbA1c

full_hba1c_drug_merge <- clean_hba1c_medcodes %>%
  
  inner_join(drug_start_dates, by="patid") %>%
  mutate(hba1cdrugdiff=datediff(hba1cdate, dstartdate)) %>%
  
  rename(hba1c=testvalue,
         hba1cdate=date) %>%

analysis$cached("full_hba1c_drug_merge", indexes=c("patid", "dstartdate","drugclass"))


############################################################################################

# Find baseline values
## Within period defined above (-2 years to +7 days for all except HbA1c and height)
## Then use closest date to drug start date
## May be multiple values; use minimum test result, except for eGFR - use maximum
## Can get duplicates where person has identical results on the same day/days equidistant from the drug start date - choose first row when ordered by drugdatediff

baseline_biomarkers <- drug_start_stop %>%
  select(patid, dstartdate, drugclass, druginstance)


## For all except HbA1c and height: between 2 years prior and 7 days after drug start date

biomarkers_no_height <- setdiff(biomarkers, "height")

for (i in biomarkers_no_height) {
  
  print(i)
  
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  interim_baseline_biomarker_table <- paste0("baseline_biomarkers_interim_", i)
  pre_biomarker_variable <- paste0("pre", i)
  pre_biomarker_date_variable <- paste0("pre", i, "date")
  pre_biomarker_drugdiff_variable <- paste0("pre", i, "drugdiff")
  
  
  data <- get(drug_merge_tablename) %>%
    filter(drugdatediff<=7 & drugdatediff>=-730) %>%
    
    group_by(patid, dstartdate, drugclass) %>%
    
    mutate(min_timediff=min(abs(drugdatediff), na.rm=TRUE)) %>%
    filter(abs(drugdatediff)==min_timediff) %>%
    
    mutate(pre_biomarker=ifelse(i=="egfr", max(testvalue, na.rm=TRUE), min(testvalue, na.rm=TRUE))) %>%
    filter(pre_biomarker==testvalue) %>%
    
    dbplyr::window_order(drugdatediff) %>%
    filter(row_number()==1) %>%
    
    ungroup() %>%
    
    rename({{pre_biomarker_variable}}:=pre_biomarker,
           {{pre_biomarker_date_variable}}:=date,
           {{pre_biomarker_drugdiff_variable}}:=drugdatediff) %>%
    
    select(-c(testvalue, druginstance, min_timediff, timetochange, timetoaddrem, multi_drug_start))
  
  
  baseline_biomarkers <- baseline_biomarkers %>%
    left_join(data, by=c("patid", "dstartdate", "drugclass")) %>%
    analysis$cached(interim_baseline_biomarker_table, indexes=c("patid", "dstartdate", "drugclass"))
    
}


## Height - only keep readings at/post drug start date, and find mean

baseline_height <- full_height_drug_merge %>%
  
  filter(drugdatediff>=0) %>%
  
  group_by(patid, dstartdate, drugclass) %>%
  
  summarise(height=mean(testvalue, na.rm=TRUE)) %>%
  
  ungroup()

baseline_biomarkers <- baseline_biomarkers %>%
  left_join(baseline_height, by=c("patid", "dstartdate", "drugclass"))

  
## HbA1c: only between 6 months prior and 7 days after drug start date
## Exclude if after timeprevcombo

baseline_hba1c <- full_hba1c_drug_merge %>%
  
  filter(drugdatediff<=7 & drugdatediff>=-183) %>%
  
  group_by(patid, dstartdate, drugclass) %>%
    
  mutate(min_timediff=min(abs(drugdatediff), na.rm=TRUE)) %>%
  filter(abs(drugdatediff)==min_timediff) %>%
    
  mutate(prehba1c=min(testvalue, na.rm=TRUE)) %>%
  filter(prehba1c==testvalue) %>%
    
  dbplyr::window_order(drugdatediff) %>%
  filter(row_number()==1) %>%
  
  ungroup() %>%
    
  rename(prehba1cdate=date,
         prehba1cdrugdiff=drugdatediff) %>%
    
  select(-c(testvalue, druginstance, min_timediff, timetochange, timetoaddrem, multi_drug_start))


### timeprevcombo in combo_start_stop table

combo_start_stop <- combo_start_stop %>% analysis$cached("combo_start_stop")

baseline_hba1c <- baseline_hba1c %>%
  left_join((combo_start_stop %>% select(patid, dcstartdate, timeprevcombo)), by=c("patid", c("dstartdate"="dcstartdate"))) %>%
  filter(prehba1cdrugdiff>=0 | is.na(timeprevcombo) | (!is.na(timeprevcombo) & abs(prehba1cdrugdiff)<=timeprevcombo)) %>%
  select(-timeprevcombo)

baseline_biomarkers <- baseline_biomarkers %>%
  left_join(baseline_hba1c, by=c("patid", "dstartdate", "drugclass")) %>% 
  analysis$cached("baseline_biomarkers", indexes=c("patid", "dstartdate", "drugclass"))

