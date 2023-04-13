
# Longitudinal CKD stages already defined from all_patid_ckd_stages script
# This script: define baseline CKD stage at index date

############################################################################################

# Setup
library(tidyverse)
library(aurum)
library(EHRBiomarkr)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("prev")


############################################################################################

# Get pointer to longitudinal CKD stage table

analysis = cprd$analysis("all_patid")

ckd_stages_from_algorithm <- ckd_stages_from_algorithm %>% analysis$cached("ckd_stages_from_algorithm")
                  

################################################################################################################################

# Merge with index date to get CKD stages at index date


## Get index date

analysis = cprd$analysis("prev")

index_date <- as.Date("2020-02-01")


# Merge with CKD stages (1 row per patid)

ckd_stage_drug_merge <- cprd$tables$patient %>%
  select(patid) %>%
  left_join(ckd_stages_from_algorithm, by="patid") %>%
  mutate(preckdstage=ifelse(!is.na(stage_5) & datediff(stage_5, index_date)<=7, "stage_5",
                            ifelse(!is.na(stage_4) & datediff(stage_4, index_date)<=7, "stage_4",
                                   ifelse(!is.na(stage_3b) & datediff(stage_3b, index_date)<=7, "stage_3b",
                                          ifelse(!is.na(stage_3a) & datediff(stage_3a, index_date)<=7, "stage_3a",
                                                 ifelse(!is.na(stage_2) & datediff(stage_2, index_date)<=7, "stage_2",
                                                        ifelse(!is.na(stage_1) & datediff(stage_1, index_date)<=7, "stage_1", NA)))))),
         
         preckdstagedate=ifelse(preckdstage=="stage_5", stage_5,
                                ifelse(preckdstage=="stage_4", stage_4,
                                       ifelse(preckdstage=="stage_3b", stage_3b,
                                              ifelse(preckdstage=="stage_3a", stage_3a,
                                                     ifelse(preckdstage=="stage_2", stage_2,
                                                            ifelse(preckdstage=="stage_1", stage_1, NA)))))),
         
         preckdstagedatediff=datediff(preckdstagedate, index_date)) %>%
  
  select(patid, preckdstage, preckdstagedate, preckdstagedatediff) %>%
  
  analysis$cached("ckd_stages", unique_indexes="patid")
                                
 