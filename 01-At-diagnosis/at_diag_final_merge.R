
# Pull together static patient data from all_diabetes_cohort table with biomarker, comorbidity, and sociodemographic (smoking/alcohol) data at the index dates

############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024",cprdConf = "~/.aurum.yaml")

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
  filter(!is.na(dm_diag_date)) %>%
  select(-c(dm_diag_date_all, dm_diag_age_all)) %>%
  left_join((baseline_biomarkers %>% select(-index_date)), by="patid") %>%
  left_join(ckd_stages, by="patid") %>%
  left_join((comorbidities %>% select(-index_date)), by="patid") %>%
  left_join(smoking, by="patid") %>%
  left_join(alcohol, by="patid") %>%
  analysis$cached("final_merge", unique_indexes="patid")


############################################################################################

# Export to R data object
## Convert integer64 datatypes to double

at_diag_cohort <- collect(final_merge %>% mutate(patid=as.character(patid)))

is.integer64 <- function(x){
  class(x)=="integer64"
}

at_diag_cohort <- at_diag_cohort %>%
  mutate_if(is.integer64, as.integer)

save(at_diag_cohort, file="20230529_at_diagnosis_cohort.Rda")

