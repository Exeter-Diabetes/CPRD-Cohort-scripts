
# Pull together static patient data from all_diabetes_cohort table with biomarker, comorbidity, and sociodemographic (smoking/alcohol) data at the index dates

############################################################################################

# Setup
library(tidyverse)
library(aurum)
library(EHRBiomarkr)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("at_diag")


############################################################################################

# Get handles to pre-existing data tables

## Cohort and patient characteristics including Townsend scores
analysis = cprd$analysis("all")
diabetes_cohort <- diabetes_cohort %>% analysis$cached("diabetes_cohort")

## Baseline biomarkers plus CKD stage
analysis = cprd$analysis("at_diag")
baseline_biomarkers <- baseline_biomarkers %>% analysis$cached("baseline_biomarkers")
ckd_stages <- ckd_stages %>% analysis$cached("ckd_stages")

## Comorbidities
comorbidities <- comorbidities %>% analysis$cached("comorbidities")

## Smoking status
smoking <- smoking %>% analysis$cached("smoking")

## Alcohol status
alcohol <- alcohol %>% analysis$cached("alcohol")


############################################################################################

# Bring together

final_merge <- diabetes_cohort %>%
  left_join(baseline_biomarkers, by="patid") %>%
  left_join(ckd_stages, by="patid") %>%
  left_join(comorbidities, by="patid") %>%
  left_join(smoking, by="patid") %>%
  left_join(alcohol, by="patid") %>%
  analysis$cached("final_merge", unique_indexes="patid")
