
# Extracts dates for non-diabetes medication scripts in GP records

# Merges with index dates

# Then finds earliest pre-index date, latest pre-index date, and earliest post-index date script for each patid

############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "01/06/2024")

analysis = cprd$analysis("at_diag")


############################################################################################

# Define medications

## Haven't included definite_genital_infection_meds, topical_candidal_meds, immunosuppressants, oralsteroids, oestrogens or flu vaccine as not updated

meds <- c("ace_inhibitors",
          "beta_blockers",
          "ca_channel_blockers",
          "thiazide_diuretics",
          "loop_diuretics",
          "ksparing_diuretics",
          "statins",
          "arb",
          "finerenone")


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

# Clean scripts (remove if before DOB or after lcd/deregistration), then merge with index dates

# Get index dates

analysis = cprd$analysis("all")

diabetes_cohort <- diabetes_cohort %>% analysis$cached("diabetes_cohort")

index_dates <- diabetes_cohort %>%
  filter(!is.na(dm_diag_date)) %>%
  select(patid, index_date=dm_diag_date)


# Clean scripts and combine with index dates

analysis = cprd$analysis("at_diag")

for (i in meds) {
  
  print(i)
  
  raw_tablename <- paste0("raw_", i, "_prodcodes")
  index_date_merge_tablename <- paste0("full_", i, "_diag_merge")
  
  data <- get(raw_tablename) %>%
    
    inner_join(cprd$tables$validDateLookup, by="patid") %>%
    filter(date>=min_dob & date<=gp_end_date) %>%
    select(patid, date) %>%
    
    inner_join(index_dates, by="patid") %>%
    mutate(datediff=datediff(date, index_date)) %>%
    
    analysis$cached(index_date_merge_tablename, index="patid")
  
  assign(index_date_merge_tablename, data)
  
}


############################################################################################

# Find earliest pre-index date, latest pre-index date and first post-index date dates

non_diabetes_meds <- index_dates


for (i in meds) {
  
  print(paste("working out pre-index date and post-index date code occurrences for", i))
  
  index_date_merge_tablename <- paste0("full_", i, "_diag_merge")
  interim_non_diab_meds_table <- paste0("non_diabetes_meds_interim_", i)
  pre_index_date_earliest_date_variable <- paste0("pre_index_date_earliest_", i, "")
  pre_index_date_latest_date_variable <- paste0("pre_index_date_latest_", i, "")
  post_index_date_date_variable <- paste0("post_index_date_first_", i, "")
  
  pre_index_date <- get(index_date_merge_tablename) %>%
    filter(date<=index_date) %>%
    group_by(patid) %>%
    summarise({{pre_index_date_earliest_date_variable}}:=min(date, na.rm=TRUE),
              {{pre_index_date_latest_date_variable}}:=max(date, na.rm=TRUE)) %>%
    ungroup()
  
  post_index_date <- get(index_date_merge_tablename) %>%
    group_by(patid) %>%
    summarise({{post_index_date_date_variable}}:=min(date, na.rm=TRUE)) %>%
    ungroup()
  
  non_diabetes_meds <- non_diabetes_meds %>%
    left_join(pre_index_date, by="patid") %>%
    left_join(post_index_date, by="patid") %>%
    analysis$cached(interim_non_diab_meds_table, unique_indexes="patid")

}


# Cache final version

non_diabetes_meds <- non_diabetes_meds %>%
  analysis$cached("non_diabetes_meds", unique_indexes="patid")




