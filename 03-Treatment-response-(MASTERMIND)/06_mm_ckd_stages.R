
# Longitudinal CKD stages already defined from all_patid_ckd_stages script
# This script: define baseline CKD stage at each drug start date

############################################################################################

# Setup
library(tidyverse)
library(aurum)
library(EHRBiomarkr)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024", cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("mm")


############################################################################################

# Get pointer to longitudinal CKD stage table

analysis = cprd$analysis("all_patid")

ckd_stages_from_algorithm <- ckd_stages_from_algorithm %>% analysis$cached("ckd_stages_from_algorithm")
                  

################################################################################################################################

# Merge with drug start dates to get CKD stages at drug start

# Get drug start dates (1 row per drug period)

analysis = cprd$analysis("mm")

drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")


# Merge with CKD stages (1 row per patid)

ckd_stage_drug_merge <- drug_start_stop %>%
  select(patid, dstartdate, drug_class, drug_substance, drug_instance) %>%
  left_join(ckd_stages_from_algorithm, by="patid") %>%
  mutate(preckdstage=ifelse(!is.na(stage_5) & datediff(stage_5, dstartdate)<=7, "stage_5",
                            ifelse(!is.na(stage_4) & datediff(stage_4, dstartdate)<=7, "stage_4",
                                   ifelse(!is.na(stage_3b) & datediff(stage_3b, dstartdate)<=7, "stage_3b",
                                          ifelse(!is.na(stage_3a) & datediff(stage_3a, dstartdate)<=7, "stage_3a",
                                                 ifelse(!is.na(stage_2) & datediff(stage_2, dstartdate)<=7, "stage_2",
                                                        ifelse(!is.na(stage_1) & datediff(stage_1, dstartdate)<=7, "stage_1", NA)))))),
         
         preckdstagedate=ifelse(preckdstage=="stage_5", stage_5,
                                ifelse(preckdstage=="stage_4", stage_4,
                                       ifelse(preckdstage=="stage_3b", stage_3b,
                                              ifelse(preckdstage=="stage_3a", stage_3a,
                                                     ifelse(preckdstage=="stage_2", stage_2,
                                                            ifelse(preckdstage=="stage_1", stage_1, NA)))))),
         
         preckdstagedrugdiff=datediff(preckdstagedate, dstartdate),
         
         postckdstage345date=
           pmin(
             ifelse(!is.na(stage_3a) & datediff(stage_3a, dstartdate)>7, stage_3a, as.Date("2050-01-01")),
             ifelse(!is.na(stage_3b) & datediff(stage_3b, dstartdate)>7, stage_3b, as.Date("2050-01-01")),
             ifelse(!is.na(stage_4) & datediff(stage_4, dstartdate)>7, stage_4, as.Date("2050-01-01")),
             ifelse(!is.na(stage_5) & datediff(stage_5, dstartdate)>7, stage_5, as.Date("2050-01-01")), na.rm=TRUE
           ),
        
         postckdstage5date=ifelse(!is.na(stage_5) & datediff(stage_5, dstartdate)>7, stage_5, NA)) %>%
  
  mutate(postckdstage345date=ifelse(postckdstage345date==as.Date("2050-01-01"), as.Date(NA), postckdstage345date)) %>%
  
  select(patid, dstartdate, drug_class, drug_substance, drug_instance, preckdstagedate, preckdstagedrugdiff, preckdstage, postckdstage5date, postckdstage345date) %>%
  
  analysis$cached("ckd_stages", indexes=c("patid", "dstartdate", "drug_substance"))
                                
 