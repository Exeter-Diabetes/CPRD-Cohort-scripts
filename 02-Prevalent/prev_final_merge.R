
# Pull together static patient data from all_diabetes_cohort table with biomarker, comorbidity, and sociodemographic (smoking/alcohol) data at the index dates
## Add in age and duration of diabetes at index date, plus QRISK2 and QDiabetes-Heart Failure scores at index date

############################################################################################

# Setup
library(tidyverse)
library(aurum)
library(EHRBiomarkr)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-2020",cprdConf = "~/.aurum.yaml")

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

cohort_ids %>% count()
#613,318

## If same diabetes codelists had been used for extract and for finding diagnosis dates, then everyone would be diagnosed before 01/02/2020 as extract specifications were that they had to have a diabetes-related medcode with at least one year of data (up to October 2020) afterwards. However, diabetes codelist used for diagnosis dates is narrower and so some people have diagnosis dates after 01/02/2020.


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
  relocate(tds_2011, .after=imd2015_10) %>%
  analysis$cached("final_merge_interim_1", unique_indexes="patid")


############################################################################################

# Add in 5 year QDiabetes-HF score and QRISK2 score

## Make separate table with additional variables for QRISK2 and QDiabetes-HF

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
         bp_meds=ifelse(earliest_bp_med!=as.Date("2050-01-01") & latest_bp_med!=as.Date("1900-01-01") & datediff(index_date, latest_bp_med)<=28 & earliest_bp_med!=latest_bp_med, 1L, 0L),
         
         type1=0L,
         type2=1L,
         surv_5yr=5L,
         surv_10yr=10L) %>%
  
  select(patid, sex, index_date_age, ethnicity_qrisk2, qrisk2_smoking_cat, dm_duration_cat, bp_meds, type1, type2, cvd, ckd45, pre_index_date_fh_premature_cvd, pre_index_date_af, pre_index_date_rheumatoidarthritis, prehba1c2yrs, precholhdl, presbp, prebmi, tds_2011, surv_5yr, surv_10yr) %>%
  
  analysis$cached("final_merge_interim_q1", unique_indexes="patid")



## Calculate 5 year QDiabetes-HF and 5 year and 10 year QRISK2 scores
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
  
  calculate_qdiabeteshf(sex=sex2, age=index_date_age, ethrisk=ethnicity_qrisk2, smoking=qrisk2_smoking_cat, duration=dm_duration_cat, type1=type1, cvd=cvd, renal=ckd45, af=pre_index_date_af, hba1c=prehba1c2yrs, cholhdl=precholhdl, sbp=presbp, bmi=prebmi, town=tds_2011, surv=surv_5yr) %>%
  
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
                          prehba1c2yrs>=40 & prehba1c2yrs<=150 &
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
  analysis$cached("final_merge_interim_2", unique_indexes="patid")


############################################################################################

# Add in kidney risk scores

## Make separate table with additional variables

ckdpc_score_vars <- final_merge %>%
  
  mutate(sex=ifelse(gender==1, "male", ifelse(gender==2, "female", "NA")),
         
         black_ethnicity=ifelse(!is.na(ethnicity_5cat) & ethnicity_5cat==2, 1L, ifelse(is.na(ethnicity_5cat), NA, 0L)),
         
         cvd=pre_index_date_myocardialinfarction==1 | pre_index_date_revasc==1 | pre_index_date_heartfailure==1 | pre_index_date_stroke==1,
         
         oha=ifelse((!is.na(pre_index_date_latest_acarbose) & datediff(index_date, pre_index_date_latest_acarbose)<=183) | 
                      (!is.na(pre_index_date_latest_mfn) & datediff(index_date, pre_index_date_latest_mfn)<=183) |
                      (!is.na(pre_index_date_latest_dpp4) & datediff(index_date, pre_index_date_latest_dpp4)<=183) |
                      (!is.na(pre_index_date_latest_glinide) & datediff(index_date, pre_index_date_latest_glinide)<=183) |
                      (!is.na(pre_index_date_latest_glp1) & datediff(index_date, pre_index_date_latest_glp1)<=183) |
                      (!is.na(pre_index_date_latest_sglt2) & datediff(index_date, pre_index_date_latest_sglt2)<=183) |
                      (!is.na(pre_index_date_latest_su) & datediff(index_date, pre_index_date_latest_su)<=183) |
                      (!is.na(pre_index_date_latest_tzd) & datediff(index_date, pre_index_date_latest_tzd)<=183), 1L, 0L),
         
         INS=ifelse(!is.na(pre_index_date_latest_insulin) & datediff(index_date, pre_index_date_latest_insulin)<=183, 1L, 0L),
         
         ever_smoker=ifelse(!is.na(smoking_cat) & (smoking_cat=="Ex-smoker" | smoking_cat=="Active smoker"), 1L, ifelse(is.na(smoking_cat), NA, 0L)),
         
         latest_bp_med=pmax(
           ifelse(is.na(pre_index_date_latest_ace_inhibitors), as.Date("1900-01-01"), pre_index_date_latest_ace_inhibitors),
           ifelse(is.na(pre_index_date_latest_beta_blockers), as.Date("1900-01-01"), pre_index_date_latest_beta_blockers),
           ifelse(is.na(pre_index_date_latest_calcium_channel_blockers), as.Date("1900-01-01"), pre_index_date_latest_calcium_channel_blockers),
           ifelse(is.na(pre_index_date_latest_thiazide_diuretics), as.Date("1900-01-01"), pre_index_date_latest_thiazide_diuretics),
           na.rm=TRUE
         ),
         
         bp_meds=ifelse(latest_bp_med!=as.Date("1900-01-01") & datediff(index_date, latest_bp_med)<=183, 1L, 0L),
         
         hypertension=ifelse((!is.na(presbp) & presbp>=140) | (!is.na(predbp) & predbp>=90) | bp_meds==1, 1L,0L),
         
         uacr=ifelse(!is.na(preacr), preacr, ifelse(!is.na(preacr_from_separate), preacr_from_separate, NA)),
         
         chd=pre_index_date_myocardialinfarction==1 | pre_index_date_revasc==1,
         
         current_smoker=ifelse(!is.na(smoking_cat) & smoking_cat=="Active smoker", 1L, ifelse(is.na(smoking_cat), NA, 0L)),
         
         ex_smoker=ifelse(!is.na(smoking_cat) & smoking_cat=="Ex-smoker", 1L, ifelse(is.na(smoking_cat), NA, 0L))) %>%
  
  select(patid, index_date_age, sex, black_ethnicity, preegfr, cvd, prehba1c2yrs, INS, oha, ever_smoker, hypertension, prebmi, uacr, presbp, bp_meds, pre_index_date_heartfailure, chd, pre_index_date_af, current_smoker, ex_smoker, preckdstage) %>%
  
  analysis$cached("final_merge_interim_ckd1", unique_indexes="patid")



### Calculate CKD risk score (5-year eGFR<60 risk + 3-year 40% decline in eGFR/renal failure)
### For some reason it doesn't like collation of sex variable unless remake it

## Remove for either if eGFR<60 (have only coded up version of second model for those with eGFR>=60)

## Also remove eGFR<60 score for those with biomarker values outside of range:
### Age: 20-80
### UACR: 0.6-56.5 (5-500 in mg/g)
### BMI: 20-40
### HbA1c 42-97 (6-11 in %)

## Also remove 40% decline in eGFR score for those with biomarker values outside of range:
### Age: 20-80
### UACR: 0.6-113 (5-1000 in mg/g)
### SBP: 80-180
### BMI: 20-40
### HbA1c 42-97 (6-11 in %)

ckdpc_scores <- ckdpc_score_vars %>%
  
  mutate(sex2=ifelse(sex=="male", "male", ifelse(sex=="female", "female", NA))) %>%
  
  calculate_ckdpc_egfr60_risk(age=index_date_age, sex=sex2, black_eth=black_ethnicity, egfr=preegfr, cvd=cvd, hba1c=prehba1c2yrs, insulin=INS, oha=oha, ever_smoker=ever_smoker, hypertension=hypertension, bmi=prebmi, acr=uacr, complete_acr=TRUE, remote=TRUE) %>%
  
  rename(ckdpc_egfr60_total_score_complete_acr=ckdpc_egfr60_total_score, ckdpc_egfr60_total_lin_predictor_complete_acr=ckdpc_egfr60_total_lin_predictor, ckdpc_egfr60_confirmed_score_complete_acr=ckdpc_egfr60_confirmed_score, ckdpc_egfr60_confirmed_lin_predictor_complete_acr=ckdpc_egfr60_confirmed_lin_predictor) %>%
  
  analysis$cached("final_merge_interim_ckd2", unique_indexes="patid")



ckdpc_scores <- ckdpc_scores %>%
  
  mutate(sex2=ifelse(sex=="male", "male", ifelse(sex=="female", "female", NA))) %>%
  
  calculate_ckdpc_egfr60_risk(age=index_date_age, sex=sex2, black_eth=black_ethnicity, egfr=preegfr, cvd=cvd, hba1c=prehba1c2yrs, insulin=INS, oha=oha, ever_smoker=ever_smoker, hypertension=hypertension, bmi=prebmi, acr=uacr, remote=TRUE) %>%
  
  analysis$cached("final_merge_interim_ckd3", unique_indexes="patid")



ckdpc_scores <- ckdpc_scores %>%
  
  mutate(sex2=ifelse(sex=="male", "male", ifelse(sex=="female", "female", NA))) %>%
  
  calculate_ckdpc_40egfr_risk(age=index_date_age, sex=sex2, egfr=preegfr, acr=uacr, sbp=presbp, bp_meds=bp_meds, hf=pre_index_date_heartfailure, chd=chd, af=pre_index_date_af, current_smoker=current_smoker, ex_smoker=ex_smoker, bmi=prebmi, hba1c=prehba1c2yrs, oha=oha, insulin=INS, remote=TRUE) %>%
  
  mutate(across(starts_with("ckdpc_egfr60"),
                ~ifelse((is.na(preckdstage) | preckdstage=="stage_1" | preckdstage=="stage_2") &
                          (is.na(preegfr) | preegfr>=60) &
                          index_date_age>=20 & index_date_age<=80 &
                          prebmi>=20, .x, NA))) %>%
  
  mutate(across(starts_with("ckdpc_40egfr"),
                ~ifelse((is.na(preckdstage) | preckdstage=="stage_1" | preckdstage=="stage_2") &
                          (is.na(preegfr) | preegfr>=60) &
                          index_date_age>=20 & index_date_age<=80 &
                          prebmi>=20, .x, NA))) %>%
  
  select(patid, ckdpc_egfr60_total_score_complete_acr, ckdpc_egfr60_total_lin_predictor_complete_acr, ckdpc_egfr60_confirmed_score_complete_acr, ckdpc_egfr60_confirmed_lin_predictor_complete_acr, ckdpc_egfr60_total_score, ckdpc_egfr60_total_lin_predictor, ckdpc_egfr60_confirmed_score, ckdpc_egfr60_confirmed_lin_predictor, ckdpc_40egfr_score, ckdpc_40egfr_lin_predictor) %>%
  
  analysis$cached("final_merge_interim_ckd4", unique_indexes="patid")



## Join with main dataset

final_merge <- final_merge %>%
  left_join(ckdpc_scores, by="patid") %>%
  analysis$cached("final_merge", unique_indexes="patid")


############################################################################################

# Export to R data object
## Convert integer64 datatypes to double

prev_cohort <- collect(final_merge %>% mutate(patid=as.character(patid)))

is.integer64 <- function(x){
  class(x)=="integer64"
}

prev_cohort <- prev_cohort %>%
  mutate_if(is.integer64, as.integer)

save(prev_cohort, file="20240614_prev_2020_cohort.Rda")
