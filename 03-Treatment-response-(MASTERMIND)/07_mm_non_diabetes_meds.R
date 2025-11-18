
# Extracts dates for non-diabetes medication scripts in GP records

# Merges with drug start and stop dates

# Then finds earliest predrug, latest predrug, and earliest postdrug script for each drug

############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "01/06/2024")

analysis = cprd$analysis("mm")


############################################################################################

# Define medications

## Haven't included immunosuppressants, oestrogens or flu vaccine as not updated

meds <- c("ace_inhibitors",
          "beta_blockers",
          "ca_channel_blockers",
          "thiazide_diuretics",
          "loop_diuretics",
          "ksparing_diuretics",
          "statins",
          "arb",
          "finerenone",
          "oralsteroids",
          "definite_genital_infection_meds",
          "topical_candidal_meds")


############################################################################################

# Pull out raw script instances and cache with 'all_patid' prefix
## Some of these already exist from previous analyses

analysis = cprd$analysis("all_patid")

for (i in meds) {
  
  print(i)
  
  raw_tablename <- paste0("raw_", i, "_prodcodes")
  
  data <- cprd$tables$drugIssue %>%
    inner_join(codes[[i]], by="prodcodeid") %>%
    select(patid, date=issuedate) %>%
    analysis$cached(raw_tablename, indexes=c("patid", "date"))
  
  assign(raw_tablename, data)
  
}


############################################################################################

# Clean scripts (remove if before DOB or after lcd/deregistration), then merge with drug start dates
## NB: for biomarkers, cleaning and combining with drug start dates is 2 separate steps with caching between, but as there are fewer cleaning steps for meds I have made this one step here

# Get drug start dates

analysis = cprd$analysis("mm")

drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")


# Clean scripts and combine with drug start dates

for (i in meds) {
  
  print(i)
  
  raw_tablename <- paste0("raw_", i, "_prodcodes")
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  
  data <- get(raw_tablename) %>%
    
    inner_join(cprd$tables$validDateLookup, by="patid") %>%
    filter(date>=min_dob & date<=gp_end_date) %>%
    select(patid, date) %>%
    
    inner_join((drug_start_stop %>% select(patid, dstartdate, drug_class, drug_substance, drug_instance)), by="patid") %>%
    mutate(drugdatediff=datediff(date, dstartdate)) %>%
    
    analysis$cached(drug_merge_tablename, indexes=c("patid", "dstartdate", "drug_class", "drug_substance"))
  
  assign(drug_merge_tablename, data)
  
}


############################################################################################

# Find earliest predrug, latest predrug and first postdrug date
## Remove topical_candidal_meds as needs to be used in combination with genital_infection_nonspec (see script 04_mm_comorbidities)

meds <- setdiff(meds, "topical_candidal_meds")

non_diabetes_meds <- drug_start_stop %>%
  select(patid, dstartdate, drug_class, drug_substance, drug_instance)


for (i in meds) {
  
  print(paste("working out predrug and postdrug code occurrences for", i))
  
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  interim_non_diab_meds_table <- paste0("non_diabetes_meds_interim_", i)
  predrug_earliest_date_variable <- paste0("predrug_earliest_", i, "")
  predrug_latest_date_variable <- paste0("predrug_latest_", i, "")
  postdrug_date_variable <- paste0("postdrug_first_", i, "")
  
  predrug <- get(drug_merge_tablename) %>%
    filter(date<=dstartdate) %>%
    group_by(patid, dstartdate, drug_substance) %>%
    summarise({{predrug_earliest_date_variable}}:=min(date, na.rm=TRUE),
              {{predrug_latest_date_variable}}:=max(date, na.rm=TRUE)) %>%
    ungroup()
  
  postdrug <- get(drug_merge_tablename) %>%
    filter(date>dstartdate) %>%
    group_by(patid, dstartdate, drug_substance) %>%
    summarise({{postdrug_date_variable}}:=min(date, na.rm=TRUE)) %>%
    ungroup()
  
  non_diabetes_meds <- non_diabetes_meds %>%
    left_join(predrug, by=c("patid", "dstartdate", "drug_substance")) %>%
    left_join(postdrug, by=c("patid", "dstartdate", "drug_substance")) %>%
    analysis$cached(interim_non_diab_meds_table, indexes=c("patid", "dstartdate", "drug_substance"))

}


# Cache final version and rename definite_genital_infection_meds to prodspecific_gi

non_diabetes_meds <- non_diabetes_meds %>%
  rename(predrug_earliest_prodspecific_gi=predrug_earliest_definite_genital_infection_meds,
         predrug_latest_prodspecific_gi=predrug_latest_definite_genital_infection_meds,
         postdrug_first_prodspecific_gi=postdrug_first_definite_genital_infection_meds) %>%
  analysis$cached("non_diabetes_meds", indexes=c("patid", "dstartdate", "drug_substance"))




