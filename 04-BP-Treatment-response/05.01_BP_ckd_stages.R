
# Longitudinal CKD stages already defined from all_patid_ckd_stages script
# This script: define baseline CKD stage at each drug start date

############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("pedro_BP")


############################################################################################

# Get pointer to longitudinal CKD stage table

analysis = cprd$analysis("all_patid")

ckd_stages_from_algorithm <- ckd_stages_from_algorithm %>% analysis$cached("ckd_stages_from_algorithm")


################################################################################################################################

# Merge with drug start dates to get CKD stages at drug start

# Get drug start dates (1 row per drug period)

analysis = cprd$analysis("pedro_BP")

drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")


# Merge with CKD stages (1 row per patid)

ckd_stage_drug_merge <- drug_start_stop %>%
  # select important variables
  select(patid, dstartdate, drugclass, druginstance) %>%
  # combine with ckd stages
  left_join(ckd_stages_from_algorithm, by="patid") %>%
  # create pre ckd stage variable
  mutate(preckdstage=ifelse(!is.na(stage_5) & datediff(stage_5, dstartdate)<=7, "stage_5",
                            ifelse(!is.na(stage_4) & datediff(stage_4, dstartdate)<=7, "stage_4",
                                   ifelse(!is.na(stage_3b) & datediff(stage_3b, dstartdate)<=7, "stage_3b",
                                          ifelse(!is.na(stage_3a) & datediff(stage_3a, dstartdate)<=7, "stage_3a",
                                                 ifelse(!is.na(stage_2) & datediff(stage_2, dstartdate)<=7, "stage_2",
                                                        ifelse(!is.na(stage_1) & datediff(stage_1, dstartdate)<=7, "stage_1", NA)))))),
         # date
         preckdstagedate=ifelse(preckdstage=="stage_5", stage_5,
                                ifelse(preckdstage=="stage_4", stage_4,
                                       ifelse(preckdstage=="stage_3b", stage_3b,
                                              ifelse(preckdstage=="stage_3a", stage_3a,
                                                     ifelse(preckdstage=="stage_2", stage_2,
                                                            ifelse(preckdstage=="stage_1", stage_1, NA)))))),
         
         # difference between ckd date and drug start date
         preckdstagedrugdiff=datediff(preckdstagedate, dstartdate),
         
         # post ckd stage 345 date
         postckdstage345date=
           pmin(
             ifelse(!is.na(stage_3a) & datediff(stage_3a, dstartdate)>7, stage_3a, as.Date("2050-01-01")),
             ifelse(!is.na(stage_3b) & datediff(stage_3b, dstartdate)>7, stage_3b, as.Date("2050-01-01")),
             ifelse(!is.na(stage_4) & datediff(stage_4, dstartdate)>7, stage_4, as.Date("2050-01-01")),
             ifelse(!is.na(stage_5) & datediff(stage_5, dstartdate)>7, stage_5, as.Date("2050-01-01")), na.rm=TRUE
           ),
         
         # post ckd stage 5 date
         postckdstage5date=ifelse(!is.na(stage_5) & datediff(stage_5, dstartdate)>7, stage_5, NA)) %>%
  
  # change date to NA 
  mutate(postckdstage345date=ifelse(postckdstage345date==as.Date("2050-01-01"), as.Date(NA), postckdstage345date)) %>%
  
  # select important variable
  select(patid, dstartdate, drugclass, druginstance, preckdstagedate, preckdstagedrugdiff, preckdstage, postckdstage5date, postckdstage345date) %>%
  # cache this table
  analysis$cached("ckd_stages", indexes=c("patid", "dstartdate", "drugclass"))
