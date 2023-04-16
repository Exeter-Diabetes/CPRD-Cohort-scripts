
# Pull together static patient data from all_diabetes_cohort table with biomarker, comorbidity, and sociodemographic (smoking/alcohol) data at the index dates
## Add in age and duration of diabetes at index date, plus QRISK2 and QDiabetes-Heart Failure scores at index date

############################################################################################

# Setup
library(tidyverse)
library(aurum)
library(EHRBiomarkr)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("prev")

index_date <- as.Date("2020-02-01")


############################################################################################

# Get handles to pre-existing data tables

## Cohort and patient characteristics including Townsend scores
analysis = cprd$analysis("all")
diabetes_cohort <- diabetes_cohort %>% analysis$cached("diabetes_cohort")
townsend_score <- townsend_score %>% analysis$cached("patid_townsend_score")

## Baseline biomarkers plus CKD stage
analysis = cprd$analysis("prev")
baseline_biomarkers <- baseline_biomarkers %>% analysis$cached("baseline_biomarkers")
ckd_stages <- ckd_stages %>% analysis$cached("ckd_stages")

## Comorbidities
comorbidities <- comorbidities %>% analysis$cached("comorbidities")

## Smoking status
smoking <- smoking %>% analysis$cached("smoking")

## Alcohol status
alcohol <- alcohol %>% analysis$cached("alcohol")

## Medications
medications <- medications %>% analysis$cached("medications")


############################################################################################

# Define prevalent cohort and add in variables from other tables plus age and diabetes duration at index date and QRISK2 and QDiabetes-HF
## Prevalent cohort: registered on 01/02/2020 and with diagnosis at/before then and with linked HES records (and n_patid_hes<=20).

cohort_ids <- diabetes_cohort %>%
  filter(dm_diag_date_all<=index_date & regstartdate<=index_date & gp_record_end>=index_date & (is.na(death_date) | death_date>=index_date) & with_hes==1) %>%
  select(patid) %>%
  analysis$cached("cohort_ids", unique_indexes="patid")


final_merge <- cohort_ids %>%
  left_join(diabetes_cohort, by="patid") %>%
  left_join((townsend_score %>% select(patid, tds_2011)), by="patid") %>%
  left_join(baseline_biomarkers, by="patid") %>%
  left_join(ckd_stages, by="patid") %>%
  left_join(comorbidities, by="patid") %>%
  left_join(smoking, by="patid") %>%
  left_join(alcohol, by="patid") %>%
  left_join(medications, by="patid") %>%
  mutate(index_date_age=datediff(index_date, dob)/365.25,
         index_date_dm_dur_all=datediff(index_date, dm_diag_date_all)/365.25) %>%
  relocate(c(index_date_age, index_date_dm_dur_all), .before=gender) %>%
  relocate(tds_2011, after=imd2015_10) %>%
  analysis$cached("final_merge_interim_1", unique_indexes="patid")


### Make separate table with additional variables for QRISK2 and QDiabetes-HF

qscore_vars <- final_merge %>%
  mutate(precholhdl=pretotalcholesterol/prehdl,
         ckd45=!is.na(preckdstage) & (preckdstage=="stage_4" | preckdstage=="stage_5"),
         cvd=pre_index_date_myocardialinfarction==1 | pre_index_date_angina==1 | pre_index_date_stroke==1,
         sex=ifelse(gender==1, "male", ifelse(gender==2, "female", "NA")),
         dm_duration_cat=ifelse(index_date_dm_dur_all<=1, 0L,
                                ifelse(index_date_dm_dur_all<4, 1L,
                                       ifelse(index_date_dm_dur_all<7, 2L,
                                              ifelse(index_date_dm_dur_all<11, 3L, 4L)))),
         
         earliest_bp_med=pmin(
           ifelse(is.na(pre_index_date_earliest_ace_inhibitors),as.Date("2050-01-01"),pre_index_date_earliest_ace_inhibitors),
           ifelse(is.na(pre_index_date_earliest_beta_blockers),as.Date("2050-01-01"),pre_index_date_earliest_beta_blockers),
           ifelse(is.na(pre_index_date_earliest_calcium_channel_blockers),as.Date("2050-01-01"),pre_index_date_earliest_calcium_channel_blockers),
           ifelse(is.na(pre_index_date_earliest_thiazide_diuretics),as.Date("2050-01-01"),pre_index_date_earliest_thiazide_diuretics),
           na.rm=TRUE
         ),
         latest_bp_med=pmax(
           ifelse(is.na(pre_index_date_latest_ace_inhibitors),as.Date("1900-01-01"),pre_index_date_latest_ace_inhibitors),
           ifelse(is.na(pre_index_date_latest_beta_blockers),as.Date("1900-01-01"),pre_index_date_latest_beta_blockers),
           ifelse(is.na(pre_index_date_latest_calcium_channel_blockers),as.Date("1900-01-01"),pre_index_date_latest_calcium_channel_blockers),
           ifelse(is.na(pre_index_date_latest_thiazide_diuretics),as.Date("1900-01-01"),pre_index_date_latest_thiazide_diuretics),
           na.rm=TRUE
         ),
         bp_meds=ifelse(earliest_bp_med!=as.Date("2050-01-01") & latest_bp_med!=as.Date("1900-01-01") & datediff(latest_bp_med, index_date)<=28 & earliest_bp_med!=latest_bp_med, 1L, 0L),
         
         type1=0L,
         type2=1L,
         surv_5yr=5L,
         surv_10yr=10L) %>%
  
  select(patid, sex, index_date_age, ethnicity_qrisk2, qrisk2_smoking_cat, dm_duration_cat, bp_meds, type1, type2, cvd, ckd45, pre_index_date_fh_premature_cvd, pre_index_date_af, pre_index_date_rheumatoidarthritis, prehba1c, precholhdl, presbp, prebmi, tds_2011, surv_5yr, surv_10yr) %>%
  
  analysis$cached("final_merge_interim_q1", unique_indexes="patid")



### Calculate 5 year QDiabetes-HF and 5 year and 10 year QRISK2 scores
### For some reason it doesn't like collation of sex variable unless remake it

## Remove QDiabetes-HF score for those with biomarker values outside of range:
### CholHDL: missing or 1-11 (NOT 12)
### HbA1c: 40-150
### SBP: missing or 70-210
### Age: 25-84
### Also exclude if BMI<20 as v. different from development cohort

## Remove QRISK2 score for those with biomarker values outside of range:
### CholHDL: missing or 1-12
### SBP: missing or 70-210
### Age: 25-84
### Also exclude if BMI<20 as v. different from development cohort

qscores <- qscore_vars %>%
  
  mutate(sex2=ifelse(sex=="male", "male", ifelse(sex=="female", "female", NA))) %>%
  
  calculate_qdiabeteshf(sex=sex2, age=index_date_age, ethrisk=ethnicity_qrisk2, smoking=qrisk2_smoking_cat, duration=dm_duration_cat, type1=type1, cvd=cvd, renal=ckd45, af=pre_index_date_af, hba1c=prehba1c, cholhdl=precholhdl, sbp=presbp, bmi=prebmi, town=tds_2011, surv=surv_5yr) %>%
  
  rename(qdiabeteshf_5yr_score=qdiabeteshf_score) %>%
  
  analysis$cached("final_merge_interim_q2", unique_indexes="patid")



qscores <- qscores %>%
  
  mutate(sex2=ifelse(sex=="male", "male", ifelse(sex=="female", "female", NA))) %>%
  
  calculate_qrisk2(sex=sex2, age=index_date_age, ethrisk=ethnicity_qrisk2, smoking=qrisk2_smoking_cat, type1=type1, type2=type2, fh_cvd=pre_index_date_fh_premature_cvd, renal=ckd45, af=pre_index_date_af, rheumatoid_arth=pre_index_date_rheumatoidarthritis, cholhdl=precholhdl, sbp=presbp, bmi=prebmi, bp_med=bp_meds, town=tds_2011, surv=surv_5yr) %>%
  
  rename(qrisk2_5yr_score=qrisk2_score) %>%
  
  select(-qrisk2_lin_predictor) %>%
  
  analysis$cached("final_merge_interim_q3", unique_indexes="patid")



qscores <- qscores %>%
  
  mutate(sex2=ifelse(sex=="male", "male", ifelse(sex=="female", "female", NA))) %>%
  
  calculate_qrisk2(sex=sex2, age=index_date_age, ethrisk=ethnicity_qrisk2, smoking=qrisk2_smoking_cat, type1=type1, type2=type2, fh_cvd=pre_index_date_fh_premature_cvd, renal=ckd45, af=pre_index_date_af, rheumatoid_arth=pre_index_date_rheumatoidarthritis, cholhdl=precholhdl, sbp=presbp, bmi=prebmi, bp_med=bp_meds, town=tds_2011, surv=surv_10yr) %>%
  
  rename(qrisk2_10yr_score=qrisk2_score) %>%
  
  mutate(across(starts_with("qdiabeteshf"),
                ~ifelse((is.na(precholhdl) | (precholhdl>=1 & precholhdl<=11)) &
                          prehba1c>=40 & prehba1c<=150 &
                          (is.na(presbp) | (presbp>=70 & presbp<=210)) &
                          index_date_age>=25 & index_date_age<=84 &
                          (is.na(prebmi) | prebmi>=20), .x, NA))) %>%
  
  mutate(across(starts_with("qrisk2"),
                ~ifelse((is.na(precholhdl) | (precholhdl>=1 & precholhdl<=12)) &
                          (is.na(presbp) | (presbp>=70 & presbp<=210)) &
                          index_date_age>=25 & index_date_age<=84 &
                          (is.na(prebmi) | prebmi>=20), .x, NA))) %>%
  
  select(patid, qdiabeteshf_5yr_score, qdiabeteshf_lin_predictor, qrisk2_5yr_score, qrisk2_10yr_score, qrisk2_lin_predictor) %>%
  
  analysis$cached("final_merge_interim_q4", unique_indexes="patid")


## Join with main dataset

final_merge <- final_merge %>%
  left_join(qscores, by="patid") %>%
  analysis$cached("final_merge", unique_indexes="patid")

