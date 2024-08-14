
# Makes binary variables for whether primary or any causes of death are:
## CV
## Heart failure

# Final table is 1 row per patid, don't need 1 row per drug period as all drug periods are prior to death

############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

analysis = cprd$analysis("pedro_BP")


############################################################################################

# Add in CV and HF death outcomes
## Do for all IDs as quicker
## No patid duplicates in ONS death table so dont need to worry about these

death_causes <- cprd$tables$onsDeath %>%
  select(patid, starts_with("cause")) %>%
  rename(primary_death_cause=cause,
         secondary_death_cause1=cause1,
         secondary_death_cause2=cause2,
         secondary_death_cause3=cause3,
         secondary_death_cause4=cause4,
         secondary_death_cause5=cause5,
         secondary_death_cause6=cause6,
         secondary_death_cause7=cause7,
         secondary_death_cause8=cause8,
         secondary_death_cause9=cause9,
         secondary_death_cause10=cause10,
         secondary_death_cause11=cause11,
         secondary_death_cause12=cause12,
         secondary_death_cause13=cause13,
         secondary_death_cause14=cause14,
         secondary_death_cause15=cause15)


# Primary cause

cv_death_primary <- death_causes %>%
  inner_join(codes$icd10_cv_death, sql_on="LHS.primary_death_cause LIKE CONCAT(icd10,'%')") %>%
  select(patid) %>%
  mutate(cv_death_primary_cause=1L) %>%
  analysis$cached("death_cv_primary", unique_indexes="patid")

hf_death_primary <- death_causes %>%
  inner_join(codes$icd10_heartfailure, sql_on="LHS.primary_death_cause LIKE CONCAT(icd10,'%')") %>%
  select(patid)%>%
  mutate(hf_death_primary_cause=1L) %>%
  analysis$cached("death_hf_primary", unique_indexes="patid")


# Secondary causes
## Reshape as easier

secondary_death_causes <- death_causes %>%
  select(patid, secondary_death_cause1:secondary_death_cause15) %>%
  pivot_longer(cols=-patid, values_to="secondary_death_cause")

cv_death_secondary <- secondary_death_causes %>%
  inner_join(codes$icd10_cv_death, sql_on="LHS.secondary_death_cause LIKE CONCAT(icd10,'%')") %>%
  distinct(patid) %>%
  analysis$cached("death_cv_secondary", unique_indexes="patid")

hf_death_secondary <- secondary_death_causes %>%
  inner_join(codes$icd10_heartfailure, sql_on="LHS.secondary_death_cause LIKE CONCAT(icd10,'%')") %>%
  distinct(patid) %>%
  analysis$cached("death_hf_secondary", unique_indexes="patid")


# Join primary and secondary for any cause

cv_death_any <- cv_death_primary %>%
  select(-cv_death_primary_cause) %>%
  union(cv_death_secondary) %>%
  mutate(cv_death_any_cause=1L) %>%
  analysis$cached("death_cv_any", unique_indexes="patid")

hf_death_any <- hf_death_primary%>%
  select(-hf_death_primary_cause) %>%
  union(hf_death_secondary) %>%
  mutate(hf_death_any_cause=1L) %>%
  analysis$cached("death_hf_any", unique_indexes="patid")


## Join together and with all primary and secondary cause

death_causes <- cprd$tables$onsDeath %>%
  select(patid, starts_with("cause")) %>%
  rename(primary_death_cause=cause,
         secondary_death_cause1=cause1,
         secondary_death_cause2=cause2,
         secondary_death_cause3=cause3,
         secondary_death_cause4=cause4,
         secondary_death_cause5=cause5,
         secondary_death_cause6=cause6,
         secondary_death_cause7=cause7,
         secondary_death_cause8=cause8,
         secondary_death_cause9=cause9,
         secondary_death_cause10=cause10,
         secondary_death_cause11=cause11,
         secondary_death_cause12=cause12,
         secondary_death_cause13=cause13,
         secondary_death_cause14=cause14,
         secondary_death_cause15=cause15) %>%
  left_join(cv_death_primary, by="patid") %>%
  left_join(cv_death_any, by="patid") %>%
  left_join(hf_death_primary, by="patid") %>%
  left_join(hf_death_any, by="patid") %>%
  analysis$cached("death_causes", unique_indexes="patid")