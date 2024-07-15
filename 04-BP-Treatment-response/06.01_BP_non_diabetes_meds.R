
# Extracts dates for non-diabetes medication scripts in GP records

# Merges with drug start and stop dates

# Then finds earliest predrug, latest predrug, and earliest postdrug script for each drug

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

# Define medications

meds <- c("ace_inhibitors",
          "beta_blockers",
          "calcium_channel_blockers",
          "thiazide_diuretics",
          "loop_diuretics",
          "ksparing_diuretics",
          "definite_genital_infection_meds",
          "topical_candidal_meds",
          "immunosuppressants",
          "oralsteroids",
          "oestrogens",
          "statins",
          "fluvacc_stopflu_prod",
          "arb")


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

# Clean scripts (remove if before DOB or after lcd/deregistration/death), then merge with drug start dates
## NB: for biomarkers, cleaning and combining with drug start dates is 2 separate steps with caching between, but as there are fewer cleaning steps for meds I have made this one step here

# Get drug start dates

analysis = cprd$analysis("pedro_BP")

drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")


# Clean scripts and combine with drug start dates

for (i in meds) {
  
  print(i)
  
  raw_tablename <- paste0("raw_", i, "_prodcodes")
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  
  data <- get(raw_tablename) %>%
    
    inner_join(cprd$tables$validDateLookup, by="patid") %>%
    filter(date>=min_dob & date<=gp_ons_end_date) %>%
    select(patid, date) %>%
    
    inner_join((drug_start_stop %>% select(patid, dstartdate, drugclass, druginstance)), by="patid") %>%
    mutate(drugdatediff=datediff(date, dstartdate)) %>%
    
    analysis$cached(drug_merge_tablename, indexes=c("patid", "dstartdate", "drugclass"))
  
  assign(drug_merge_tablename, data)
  
}


############################################################################################

# Find earliest predrug, latest predrug and first postdrug dates
## Remove definite_genital_infection_meds / fluvacc_stopflu_prod as need to be used in combination with genital_infection_nonspec / fluvacc_stopflu_med medcodes (see script 4_mm_comorbidities)

meds <- setdiff(meds, c("definite_genital_infection_meds", "fluvacc_stopflu_prod"))

non_diabetes_meds <- drug_start_stop %>%
  select(patid, dstartdate, drugclass, druginstance)


for (i in meds) {
  
  print(paste("working out predrug and postdrug code occurrences for", i))
  
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  interim_non_diab_meds_table <- paste0("non_diabetes_meds_interim_", i)
  predrug_earliest_date_variable <- paste0("predrug_earliest_", i, "")
  predrug_latest_date_variable <- paste0("predrug_latest_", i, "")
  postdrug_date_variable <- paste0("postdrug_first_", i, "")
  
  predrug <- get(drug_merge_tablename) %>%
    filter(date<=dstartdate) %>%
    group_by(patid, dstartdate, drugclass) %>%
    summarise({{predrug_earliest_date_variable}}:=min(date, na.rm=TRUE),
              {{predrug_latest_date_variable}}:=max(date, na.rm=TRUE)) %>%
    ungroup()
  
  postdrug <- get(drug_merge_tablename) %>%
    filter(date>dstartdate) %>%
    group_by(patid, dstartdate, drugclass) %>%
    summarise({{postdrug_date_variable}}:=min(date, na.rm=TRUE)) %>%
    ungroup()
  
  non_diabetes_meds <- non_diabetes_meds %>%
    left_join(predrug, by=c("patid", "dstartdate", "drugclass")) %>%
    left_join(postdrug, by=c("patid", "dstartdate", "drugclass")) %>%
    analysis$cached(interim_non_diab_meds_table, indexes=c("patid", "dstartdate", "drugclass"))
  
}


# Cache final version and rename topical_candidal_meds to prodspecific_gi for Laura

non_diabetes_meds <- non_diabetes_meds %>%
  rename(predrug_earliest_prodspecific_gi=predrug_earliest_topical_candidal_meds,
         predrug_latest_prodspecific_gi=predrug_latest_topical_candidal_meds,
         postdrug_first_prodspecific_gi=postdrug_first_topical_candidal_meds) %>%
  analysis$cached("non_diabetes_meds", indexes=c("patid", "dstartdate", "drugclass"))


