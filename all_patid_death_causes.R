
# Makes binary variables for whether primary or any causes of death are:
## Cardiovascular
## Heart failure
## Kidney failure

# Most deaths <2001 are recorded as ICD9 codes so will not be identified by this script

# Final table is 1 row per patid, don't need 1 row per drug period as all drug periods are prior to death

############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "01/06/2024")

analysis = cprd$analysis("all")


############################################################################################

# Add in CV, HF and KF death outcomes
## Do for all IDs as quicker
## No patid duplicates in ONS death table so don't need to worry about these
## Do have >1 underlying (primary) death cause for some people so reshape long to query these


# Primary cause

primary_death_causes <- cprd$tables$onsDeath %>%
  select(patid, starts_with("underlying_cause")) %>%
  pivot_longer(cols=-patid, names_to="name", values_to="primary_cause") %>%
  select(-name) %>%
  analysis$cached("primary_death_causes", indexes=c("patid", "primary_cause"))

cv_death_primary <- primary_death_causes %>%
  inner_join(codes$icd10_cv_death, sql_on="primary_cause LIKE CONCAT(icd10,'%')") %>%
  distinct(patid) %>%
  mutate(cv_death_primary_cause=1L) %>%
  analysis$cached("death_cv_primary", unique_indexes="patid")

hf_death_primary <- primary_death_causes %>%
  inner_join(codes$icd10_heartfailure, sql_on="primary_cause LIKE CONCAT(icd10,'%')") %>%
  distinct(patid)%>%
  mutate(hf_death_primary_cause=1L) %>%
  analysis$cached("death_hf_primary", unique_indexes="patid")

kf_death_primary <- primary_death_causes %>%
  inner_join(codes$icd10_kf_death, sql_on="primary_cause LIKE CONCAT(icd10,'%')") %>%
  distinct(patid)%>%
  mutate(kf_death_primary_cause=1L) %>%
  analysis$cached("death_kf_primary", unique_indexes="patid")

stroke_death_primary <- primary_death_causes %>%
  inner_join(codes$icd10_stroke, sql_on = "primary_cause LIKE CONCAT(icd10,'%')") %>%
  distinct(patid) %>%
  mutate(stroke_death_primary_cause = 1L) %>%
  analysis$cached("death_stroke_primary", unique_indexes = "patid")

mi_death_primary <- primary_death_causes %>%
  inner_join(
    codes$icd10_myocardialinfarction,
    sql_on = "primary_cause LIKE CONCAT(icd10,'%')"
  ) %>%
  distinct(patid) %>%
  mutate(mi_death_primary_cause = 1L) %>%
  analysis$cached("death_mi_primary", unique_indexes = "patid")


hyperglycaemia_death_primary <- primary_death_causes %>%
  inner_join(
    codes$icd10_ukpds_hyperglycaemic_death,
    sql_on = "primary_cause LIKE CONCAT(icd10,'%')"
  ) %>%
  distinct(patid) %>%
  mutate(hyperglycaemia_death_primary_cause = 1L) %>%
  analysis$cached("death_hyperglycaemia_primary", unique_indexes = "patid")

hypoglycaemia_death_primary <- primary_death_causes %>%
  inner_join(
    codes$icd10_hypoglycaemia,
    sql_on = "primary_cause LIKE CONCAT(icd10,'%')"
  ) %>%
  distinct(patid) %>%
  mutate(hypoglycaemia_death_primary_cause = 1L) %>%
  analysis$cached("death_hypoglycaemia_primary", unique_indexes = "patid")

pvd_death_primary <- primary_death_causes %>%
  inner_join(
    codes$icd10_ukpds_pvd_death,
    sql_on = "primary_cause LIKE CONCAT(icd10,'%')"
  ) %>%
  distinct(patid) %>%
  mutate(pvd_death_primary_cause = 1L) %>%
  analysis$cached("death_pvd_primary", unique_indexes = "patid")

sudden_death_primary <- primary_death_causes %>%
  inner_join(
    codes$icd10_ukpds_sudden_death,
    sql_on = "primary_cause LIKE CONCAT(icd10,'%')"
  ) %>%
  distinct(patid) %>%
  mutate(sudden_death_primary_cause = 1L) %>%
  analysis$cached("death_sudden_primary", unique_indexes = "patid")


haem_cancer_death_primary <- primary_death_causes %>%
  inner_join(
    codes$icd10_haem_cancer,
    sql_on = "primary_cause LIKE CONCAT(icd10,'%')"
  ) %>%
  distinct(patid) %>%
  mutate(haem_cancer_death_primary_cause = 1L) %>%
  analysis$cached("death_haem_cancer_primary", unique_indexes = "patid")


solid_cancer_death_primary <- primary_death_causes %>%
  inner_join(
    codes$icd10_solid_cancer,
    sql_on = "primary_cause LIKE CONCAT(icd10,'%')"
  ) %>%
  distinct(patid) %>%
  mutate(solid_cancer_death_primary_cause = 1L) %>%
  analysis$cached("death_solid_cancer_primary", unique_indexes = "patid")


any_cancer_death_primary <- haem_cancer_death_primary %>%
  select(patid) %>%
  union(solid_cancer_death_primary %>% select(patid)) %>%
  distinct(patid) %>%
  mutate(cancer_death_primary_cause = 1L) %>%
  analysis$cached("death_any_cancer_primary", unique_indexes = "patid")

pancreatic_cancer_death_primary <- primary_death_causes %>%
  inner_join(
    codes$icd10_pancreaticcancer,
    sql_on = "primary_cause LIKE CONCAT(icd10,'%')"
  ) %>%
  distinct(patid) %>%
  mutate(pancreatic_cancer_death_primary_cause = 1L) %>%
  analysis$cached("death_pancreatic_cancer_primary", unique_indexes = "patid")




# Secondary causes

secondary_death_causes <- cprd$tables$onsDeath %>%
  select(patid, starts_with("cause")) %>%
  pivot_longer(cols=-patid, names_to="name", values_to="secondary_cause") %>%
  select(-name) %>%
  analysis$cached("secondary_death_causes", indexes=c("patid", "secondary_cause"))

cv_death_secondary <- secondary_death_causes %>%
  inner_join(codes$icd10_cv_death, sql_on="secondary_cause LIKE CONCAT(icd10,'%')") %>%
  distinct(patid) %>%
  analysis$cached("death_cv_secondary", unique_indexes="patid")

hf_death_secondary <- secondary_death_causes %>%
  inner_join(codes$icd10_heartfailure, sql_on="secondary_cause LIKE CONCAT(icd10,'%')") %>%
  distinct(patid) %>%
  analysis$cached("death_hf_secondary", unique_indexes="patid")

kf_death_secondary <- secondary_death_causes %>%
  inner_join(codes$icd10_kf_death, sql_on="secondary_cause LIKE CONCAT(icd10,'%')") %>%
  distinct(patid) %>%
  analysis$cached("death_kf_secondary", unique_indexes="patid")


hyperglycaemia_death_secondary <- secondary_death_causes %>%
  inner_join(
    codes$icd10_ukpds_hyperglycaemic_death,
    sql_on = "secondary_cause LIKE CONCAT(icd10,'%')"
  ) %>%
  distinct(patid) %>%
  analysis$cached("death_hyperglycaemia_secondary", unique_indexes = "patid")

hypoglycaemia_death_secondary <- secondary_death_causes %>%
  inner_join(
    codes$icd10_hypoglycaemia,
    sql_on = "secondary_cause LIKE CONCAT(icd10,'%')"
  ) %>%
  distinct(patid) %>%
  analysis$cached("death_hypoglycaemia_secondary", unique_indexes = "patid")

pvd_death_secondary <- secondary_death_causes %>%
  inner_join(
    codes$icd10_ukpds_pvd_death,
    sql_on = "secondary_cause LIKE CONCAT(icd10,'%')"
  ) %>%
  distinct(patid) %>%
  analysis$cached("death_pvd_secondary", unique_indexes = "patid")

sudden_death_secondary <- secondary_death_causes %>%
  inner_join(
    codes$icd10_ukpds_sudden_death,
    sql_on = "secondary_cause LIKE CONCAT(icd10,'%')"
  ) %>%
  distinct(patid) %>%
  analysis$cached("death_sudden_secondary", unique_indexes = "patid")


haem_cancer_death_secondary <- secondary_death_causes %>%
  inner_join(codes$icd10_haem_cancer, sql_on = "secondary_cause LIKE CONCAT(icd10,'%')") %>%
  distinct(patid) %>%
  analysis$cached("death_haem_cancer_secondary", unique_indexes = "patid")

solid_cancer_death_secondary <- secondary_death_causes %>%
  inner_join(codes$icd10_solid_cancer, sql_on = "secondary_cause LIKE CONCAT(icd10,'%')") %>%
  distinct(patid) %>%
  analysis$cached("death_solid_cancer_secondary", unique_indexes = "patid")

cancer_death_secondary <- haem_cancer_death_secondary %>%
  select(patid) %>%
  union(solid_cancer_death_secondary %>% select(patid)) %>%
  distinct(patid) %>%
  mutate(cancer_death_secondary_cause = 1L) %>%
  analysis$cached("death_cancer_secondary", unique_indexes = "patid")

pancreatic_cancer_death_secondary <- secondary_death_causes %>%
  inner_join(
    codes$icd10_pancreaticcancer,
    sql_on = "secondary_cause LIKE CONCAT(icd10,'%')"
  ) %>%
  distinct(patid) %>%
  analysis$cached("death_pancreatic_cancer_secondary", unique_indexes = "patid")





# Join primary and secondary for any cause

cv_death_any <- cv_death_primary %>%
  select(-cv_death_primary_cause) %>%
  union(cv_death_secondary) %>%
  mutate(cv_death_any_cause=1L) %>%
  analysis$cached("death_cv_any", unique_indexes="patid")

hf_death_any <- hf_death_primary %>%
  select(-hf_death_primary_cause) %>%
  union(hf_death_secondary) %>%
  mutate(hf_death_any_cause=1L) %>%
  analysis$cached("death_hf_any", unique_indexes="patid")

kf_death_any <- kf_death_primary %>%
  select(-kf_death_primary_cause) %>%
  union(kf_death_secondary) %>%
  mutate(kf_death_any_cause=1L) %>%
  analysis$cached("death_kf_any", unique_indexes="patid")


hyperglycaemia_death_any <- hyperglycaemia_death_primary %>%
  select(-hyperglycaemia_death_primary_cause) %>%
  union(hyperglycaemia_death_secondary) %>%
  mutate(hyperglycaemia_death_any_cause = 1L) %>%
  analysis$cached("death_hyperglycaemia_any", unique_indexes = "patid")

hypoglycaemia_death_any <- hypoglycaemia_death_primary %>%
  select(-hypoglycaemia_death_primary_cause) %>%
  union(hypoglycaemia_death_secondary) %>%
  mutate(hypoglycaemia_death_any_cause = 1L) %>%
  analysis$cached("death_hypoglycaemia_any", unique_indexes = "patid")

pvd_death_any <- pvd_death_primary %>%
  select(-pvd_death_primary_cause) %>%
  union(pvd_death_secondary) %>%
  mutate(pvd_death_any_cause = 1L) %>%
  analysis$cached("death_pvd_any", unique_indexes = "patid")

sudden_death_any <- sudden_death_primary %>%
  select(-sudden_death_primary_cause) %>%
  union(sudden_death_secondary) %>%
  mutate(sudden_death_any_cause = 1L) %>%
  analysis$cached("death_sudden_any", unique_indexes = "patid")


haem_cancer_death_any <- haem_cancer_death_primary %>%
  select(patid) %>%
  union(haem_cancer_death_secondary %>% select(patid)) %>%
  distinct(patid) %>%
  mutate(haem_cancer_death_any_cause = 1L) %>%
  analysis$cached("death_haem_cancer_any", unique_indexes = "patid")

solid_cancer_death_any <- solid_cancer_death_primary %>%
  select(patid) %>%
  union(solid_cancer_death_secondary %>% select(patid)) %>%
  distinct(patid) %>%
  mutate(solid_cancer_death_any_cause = 1L) %>%
  analysis$cached("death_solid_cancer_any", unique_indexes = "patid")

any_cancer_death_any <- haem_cancer_death_any %>%
  select(patid) %>%
  union(solid_cancer_death_any %>% select(patid)) %>%
  distinct(patid) %>%
  mutate(cancer_death_any_cause = 1L) %>%
  analysis$cached("death_any_cancer_any", unique_indexes = "patid")


pancreatic_cancer_death_any <- pancreatic_cancer_death_primary %>%
  select(-pancreatic_cancer_death_primary_cause) %>%
  union(pancreatic_cancer_death_secondary) %>%
  mutate(pancreatic_cancer_death_any_cause=1L) %>%
  analysis$cached("death_pancreatic_cancer_any", unique_indexes="patid")




## Join together and with all primary and secondary cause

death_causes <- cprd$tables$onsDeath %>%
  select(patid, contains("cause")) %>%
  select(-c(contains("icd9"))) %>%
  rename(primary_death_cause1=underlying_cause_1,
         primary_death_cause2=underlying_cause_2,
         primary_death_cause3=underlying_cause_3,
         secondary_death_cause1=cause_1,
         secondary_death_cause2=cause_2,
         secondary_death_cause3=cause_3,
         secondary_death_cause4=cause_4,
         secondary_death_cause5=cause_5,
         secondary_death_cause6=cause_6,
         secondary_death_cause7=cause_7,
         secondary_death_cause8=cause_8,
         secondary_death_cause9=cause_9,
         secondary_death_cause10=cause_10,
         secondary_death_cause11=cause_11,
         secondary_death_cause12=cause_12,
         secondary_death_cause13=cause_13,
         secondary_death_cause14=cause_14,
         secondary_death_cause15=cause_15,
         secondary_death_cause16=cause_16,
         secondary_death_cause17=cause_17) %>%
  relocate(primary_death_cause1, .before=secondary_death_cause1) %>%
  relocate(primary_death_cause2, .before=secondary_death_cause1) %>%
  relocate(primary_death_cause3, .before=secondary_death_cause1) %>%
  left_join(cv_death_primary, by="patid") %>%
  left_join(cv_death_any, by="patid") %>%
  left_join(hf_death_primary, by="patid") %>%
  left_join(hf_death_any, by="patid") %>%
  left_join(kf_death_primary, by="patid") %>%
  left_join(kf_death_any, by="patid") %>%
  left_join(hyperglycaemia_death_primary, by = "patid") %>%
  left_join(hyperglycaemia_death_any, by = "patid") %>%
  left_join(hypoglycaemia_death_primary, by = "patid") %>%
  left_join(hypoglycaemia_death_any, by = "patid") %>%
  left_join(pvd_death_primary, by = "patid") %>%
  left_join(pvd_death_any, by = "patid") %>%
  left_join(sudden_death_primary, by = "patid") %>%
  left_join(sudden_death_any, by = "patid") %>%
  left_join(haem_cancer_death_primary,  by = "patid") %>%
  left_join(haem_cancer_death_any,      by = "patid") %>%
  left_join(solid_cancer_death_primary, by = "patid") %>%
  left_join(solid_cancer_death_any,     by = "patid") %>%
  left_join(any_cancer_death_primary,   by = "patid") %>%
  left_join(any_cancer_death_any,       by = "patid") %>%
  left_join(pancreatic_cancer_death_primary, by = "patid") %>%
  left_join(pancreatic_cancer_death_any, by = "patid") %>%
  left_join(stroke_death_primary, by = "patid") %>%
  left_join(mi_death_primary, by = "patid") %>%
  analysis$cached("death_causes", unique_indexes="patid")

