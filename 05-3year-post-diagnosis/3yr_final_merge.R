# Pull together static patient data from all_diabetes_cohort table with biomarker, comorbidity, and sociodemographic (smoking/alcohol) data at the 3-year index dates

############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024",cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("3yr")


############################################################################################

# Today's date for table name

today <- format(Sys.Date(), "%Y%m%d")


############################################################################################

# Get handles to pre-existing data tables

## Cohort and patient characteristics including death causes
analysis = cprd$analysis("all")
diabetes_cohort <- diabetes_cohort %>% analysis$cached("diabetes_cohort")
death_causes <- death_causes %>% analysis$cached("death_causes")

analysis = cprd$analysis("all_patid")

# Deprivation
townsend_score <- townsend_score %>% analysis$cached("townsend_score")


## Baseline biomarkers plus CKD stage
analysis = cprd$analysis("3yr")
baseline_biomarkers <- baseline_biomarkers_bmi_extended_window %>% analysis$cached("baseline_biomarkers")
ckd_stages <- ckd_stages %>% analysis$cached("ckd_stages")

## Comorbidities and eFI and nephropathy severity
comorbidities <- comorbidities %>% analysis$cached("comorbidities") %>%
  select(-c(pre_index_date_earliest_non_severe_retinopathy, 
            pre_index_date_latest_non_severe_retinopathy, 
            pre_index_date_non_severe_retinopathy,
            post_index_date_first_non_severe_retinopathy,
            pre_index_date_earliest_non_severe_neuropathy,
            pre_index_date_latest_non_severe_neuropathy,
            pre_index_date_non_severe_neuropathy,
            post_index_date_first_non_severe_neuropathy
            ))
efi <- efi %>% analysis$cached("efi")
microvascular_complications <- microvascular_complications %>% analysis$cached("microvascular_complications_relaxed")
ukpds <- ukpds %>% analysis$cached("ukpds")


## Non-diabetes meds
non_diabetes_meds <- non_diabetes_meds %>% analysis$cached("non_diabetes_meds")

## Smoking status
smoking <- smoking %>% analysis$cached("smoking")

## Alcohol status
alcohol <- alcohol %>% analysis$cached("alcohol")


############################################################################################

# Bring together and remove if index_date_3yr is missing or if death <= index_date_3yr

final_merge <- diabetes_cohort %>%
  filter(!is.na(index_date_3yr) & (is.na(death_date) | death_date>index_date_3yr)) %>%
  select(-c(dm_diag_date_all, dm_diag_age_all)) %>%
  left_join((baseline_biomarkers %>% select(-index_date)), by="patid") %>%
  left_join(ckd_stages, by="patid") %>%
  left_join((comorbidities %>% select(-index_date)), by="patid") %>%
  left_join((efi %>% select(-index_date)), by="patid") %>%
  left_join((non_diabetes_meds %>% select(-index_date)), by="patid") %>%
  left_join(smoking, by="patid") %>%
  left_join(alcohol, by="patid") %>%
  left_join(death_causes, by="patid") %>%
  left_join(townsend_score %>% select(-imd_decile), by = "patid") %>%
  left_join((microvascular_complications %>% select(-index_date)), by = "patid")%>%
  left_join(ukpds, by = "patid") %>%
  analysis$cached(paste0("final_", today), unique_indexes="patid")
