
# Pull together static patient data from all_t1t2_cohort table with biomarker, comorbidity, and sociodemographic (smoking/alcohol) data at the index dates

############################################################################################

# Setup
library(tidyverse)
library(aurum)
library(EHRBiomarkr)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")

cohort_prefix <- ""
# e.g. "mm" for treatment response (MASTERMIND) cohort

analysis = cprd$analysis(cohort_prefix)


############################################################################################

# Get handles to pre-existing data tables

## Cohort-specific IDs and index dates
index_dates <- index_dates %>% analysis$cached("index_dates")

## Cohort and patient characteristics
analysis = cprd$analysis("all")
diabetes_cohort <- diabetes_cohort %>% analysis$cached("t1t2_cohort")

## Baseline biomarkers plus CKD stage
analysis = cprd$analysis(cohort_prefix)
baseline_biomarkers <- baseline_biomarkers %>% analysis$cached("baseline_biomarkers")
ckd_stages <- ckd_stages %>% analysis$cached("ckd_stages")

## Comorbidities
comorbidities <- comorbidities %>% analysis$cached("comorbidities")

## Smoking status
smoking <- smoking %>% analysis$cached("smoking")

## Alcohol status
alcohol <- alcohol %>% analysis$cached("alcohol")


############################################################################################

# Make final merge table and add age and diabetes duration at index date

final_merge <- index_dates %>%
  left_join(diabetes_cohort, by="patid") %>%
  left_join(baseline_biomarkers, by=c("patid", "index_date")) %>%
  left_join(ckd_stages, by=c("patid", "index_date")) %>%
  left_join(comorbidities, by=c("patid", "index_date")) %>%
  left_join(smoking, by=c("patid", "index_date")) %>%
  left_join(alcohol, by=c("patid", "index_date")) %>%
  mutate(index_date_age=datediff(index_date, dob)/365.25,
         index_date_dm_dur_all=datediff(index_date, dm_diag_date_all)/365.25) %>%
  relocate(c(index_date_age, index_date_dm_dur_all), .after=index_date) %>%
  analysis$cached("final_merge", indexes=c("patid", "index_date"))

