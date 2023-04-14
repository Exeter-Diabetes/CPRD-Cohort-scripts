
# Extracts dates for diabetes medication and BP medication (for QRISK2 score) scripts in GP records

# Merges with index date

# Then finds earliest pre-index date, latest pre-index date, and earliest post-index date script for each drug

############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

analysis = cprd$analysis("prev")


############################################################################################

# Define medications

meds <- c("ace_inhibitors",
          "beta_blockers",
          "calcium_channel_blockers",
          "thiazide_diuretics",
          "loop_diuretics",
          "ksparing_diuretics")

# OHA and insulin processed separately as want to keep extra variables


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


raw_oha_prodcodes <- cprd$tables$drugIssue %>%
  inner_join(cprd$tables$ohaLookup, by="prodcodeid") %>%
  analysis$cached("raw_oha_prodcodes", indexes=c("patid", "issuedate"))

raw_insulin_prodcodes <- cprd$tables$drugIssue %>%
  inner_join(codes$insulin, by="prodcodeid") %>%
  analysis$cached("raw_insulin_prodcodes", indexes=c("patid", "issuedate"))


############################################################################################

# Clean scripts (remove if before DOB or after lcd/deregistration/death), then merge with drug start dates
## NB: for biomarkers, cleaning and combining with drug start dates is 2 separate steps with caching between, but as there are fewer cleaning steps for meds I have made this one step here

# For OHAs: clean and then separate by drug class first

clean_oha_prodcodes <- raw_oha_prodcodes %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(issuedate>=min_dob & issuedate<=gp_ons_end_date) %>%
  rename(date=issuedate) %>%
  analysis$cached("clean_oha_prodcodes", indexes=c("patid", "issuedate"))

clean_acarbose_prodcodes <- clean_oha_prodcodes %>%
  filter(Acarbose==1) %>%
  select(patid, date)

clean_dpp4_prodcodes <- clean_oha_prodcodes %>%
  filter(DPP4==1) %>%
  select(patid, date)

clean_glinide_prodcodes <- clean_oha_prodcodes %>%
  filter(Glinide==1) %>%
  select(patid, date)

clean_glp1_prodcodes <- clean_oha_prodcodes %>%
  filter(GLP1==1) %>%
  select(patid, date)

clean_mfn_prodcodes <- clean_oha_prodcodes %>%
  filter(MFN==1) %>%
  select(patid, date)

clean_sglt2_prodcodes <- clean_oha_prodcodes %>%
  filter(SGLT2==1) %>%
  select(patid, date)

clean_su_prodcodes <- clean_oha_prodcodes %>%
  filter(SU==1) %>%
  select(patid, date)

clean_tzd_prodcodes <- clean_oha_prodcodes %>%
  filter(TZD==1) %>%
  select(patid, date)


# For insulin: clean and cache, then combine with insulin from oha scripts (in combo with GLP1s) first

clean_insulin_prodcodes <- raw_insulin_prodcodes %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(issuedate>=min_dob & issuedate<=gp_ons_end_date) %>%
  rename(date=issuedate) %>%
  analysis$cached("clean_insulin_prodcodes", indexes=c("patid", "issuedate"))

clean_insulin_prodcodes <- clean_insulin_prodcodes %>%
  select(patid, date) %>%
  union_all(clean_oha_prodcodes %>%
              filter(INS==1) %>%
              select(patid, date))


# Add OHA classes and insulin to meds

meds <- c(meds, "acarbose", "dpp4", "glinide", "glp1", "mfn", "sglt2", "su", "tzd", "insulin")


# Get index date

analysis = cprd$analysis("prev")

index_date <- as.Date("2020-02-01")


# Clean scripts and combine with index date

for (i in meds) {
  
  print(i)
  
  if (i=="acarbose" | i=="dpp4" | i=="glinide" | i=="glp1" | i=="mfn" | i=="sglt2" | i=="su" | i=="tzd" | i=="insulin") {
    
    clean_tablename <- paste0("clean_", i, "_prodcodes")
    index_date_merge_tablename <- paste0("full_", i, "_index_date_merge")
    
    data <- get(clean_tablename) %>%
      mutate(datediff=datediff(date, index_date)) %>%
      analysis$cached(index_date_merge_tablename, indexes="patid")
    
    assign(index_date_merge_tablename, data)
    
  } else {
    
    raw_tablename <- paste0("raw_", i, "_prodcodes")
    index_date_merge_tablename <- paste0("full_", i, "_index_date_merge")
    
    data <- get(raw_tablename) %>%
      
      inner_join(cprd$tables$validDateLookup, by="patid") %>%
      filter(date>=min_dob & date<=gp_ons_end_date) %>%
      select(patid, date) %>%
      
      mutate(datediff=datediff(date, index_date)) %>%
      
      analysis$cached(index_date_merge_tablename, indexes="patid")
    
    assign(index_date_merge_tablename, data)
    
  }
}
    

############################################################################################

# Find earliest pre-index date, latest pre-index date and first post-index date dates


medications <- cprd$tables$patient %>%
  select(patid)


for (i in meds) {
  
  print(paste("working out pre- and post- index date code occurrences for", i))
  
  index_date_merge_tablename <- paste0("full_", i, "_index_date_merge")
  interim_medications_table <- paste0("medications_interim_", i)
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
    filter(date>index_date) %>%
    group_by(patid) %>%
    summarise({{post_index_date_date_variable}}:=min(date, na.rm=TRUE)) %>%
    ungroup()
  
  medications <- medications %>%
    left_join(pre_index_date, by="patid") %>%
    left_join(post_index_date, by="patid") %>%
    analysis$cached(interim_medications_table, unique_indexes="patid")

}


# Cache final version

medications <- medications %>% analysis$cached("medications", unique_indexes="patid")
