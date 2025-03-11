
# Processes prescriptions to find start and stop dates for drugs, and when other drug classes/substances added or remove relative to start date for drug class of interest


############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024", cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("mm")


############################################################################################

# Join and cache OHA and insulin prescriptions (already extracted in all_diabetes_cohort) to make ohaandins table

analysis = cprd$analysis("all_patid")

clean_oha_prodcodes <- clean_oha_prodcodes %>% analysis$cached("clean_oha_prodcodes")
#clean_oha_prodcodes %>% count()
# 195,224,495


clean_insulin_prodcodes <- clean_insulin_prodcodes %>% analysis$cached("clean_insulin_prodcodes")
#clean_insulin_prodcodes %>% count()
# 41,531,048


analysis = cprd$analysis("mm")

insulin <- clean_insulin_prodcodes %>%
 mutate(drug_class_1="INS",
     drug_class_2=NA,
     drug_substance_1=insulin_cat,
     drug_substance_2=NA) %>%
 select(-insulin_cat)

ohaandins <- clean_oha_prodcodes %>%
 union_all(insulin) %>%
 analysis$cached("ohaandins", indexes=c("patid", "date"))

#ohaandins %>% count()
# 236,755,543

#ohaandins %>% filter(!is.na(drug_substance_2)) %>% count()
# 2,540,170

# so should be 236,755,543 + 2,540,170 = 239,295,713 when reshape long in next step


############################################################################################

# Make ohains table: as per ohaandins but with 1 row per drug substance and duplicates for patid / date / drug substance removed

# Sort out combination medications

## Raw data has single line for combination meds - expand so there is 1 line per drug class/substance
## Raw data has drug_class_1, drug_class_2, drug_substance_1 and drug_substance_2 columns from ohaLookup; numbers match i.e. drug_class_1==drug_substance_1 etc.
## Pivotting reshapes to give 1 line per drug class/substance

## Check that no rows have NA in drug class columns - if so, will lose them at this stage


#ohaandins %>% filter(is.na(drug_class_1)) %>% count()
# 0 - perfect

ohains <- ohaandins %>%
 pivot_longer(cols=c(starts_with("drug_class"), starts_with("drug_substance")), names_to=c(".value", "row"), names_pattern="([A-Za-z]+_[A-Za-z]+)_(\\d+)") %>%
 select(-row) %>%
 filter(!is.na(drug_class)) %>%
 analysis$cached("ohains_interim_1", indexes=c("patid", "date"))
 
#ohains %>% count()
#239,295,713 - correct as above


# Remove patid/date/drug substance duplicates
## First convert all insulin to same drug substance as don't want to separate out these

#ohains %>% mutate(drug_substance=ifelse(drug_class=="INS", "Insulin", drug_substance)) %>% distinct(patid, date, drug_substance) %>% count()
#221,563,735 - should get this below

ohains <- ohains %>%
 mutate(drug_substance=ifelse(drug_class=="INS", "Insulin", drug_substance)) %>%
 group_by(patid, date, drug_class, drug_substance) %>%
 filter(row_number()==1) %>%
 ungroup() %>%
 analysis$cached("ohains", indexes=c("patid", "date"))

#ohains %>% count()
#221,563,735 = correct as above (NB: is slightly higher than when ran for Martha, as have categorised prodcodeid where we're not sure if high or low dose as its own drug substance ('Semaglutide, dose unclear'))


############################################################################################

# all_scripts_long table: as per ohains table but with start and stop variables added

# Define whether date is start or stop for each drug class
## Find time from previous script (dprevuse) and to next script (dnextuse) for same person and same drug class
## If no previous script/previous script more than 6 months (183 days) earlier, define as start date (dstart=1)
## If no next script/next script more than 6 months (183 days) later, define as stop date (dstop=1)

all_scripts_long <- ohains %>%
 group_by(patid, drug_class) %>%
 dbplyr::window_order(date) %>%
 mutate(dnextuse_class=datediff(lead(date), date),
     dprevuse_class=datediff(date, lag(date)),
     dstart_class=dprevuse_class>183 | is.na(dprevuse_class),
     dstop_class=dnextuse_class>183 | is.na(dnextuse_class)) %>%
 ungroup() %>%
 group_by(patid, drug_substance) %>%
 dbplyr::window_order(date) %>%
 mutate(dnextuse_substance=datediff(lead(date), date),
     dprevuse_substance=datediff(date, lag(date)),
     dstart_substance=dprevuse_substance>183 | is.na(dprevuse_substance),
     dstop_substance=dnextuse_substance>183 | is.na(dnextuse_substance)) %>%
 ungroup() %>%
 analysis$cached("all_scripts_long_interim_1", indexes=c("patid", "date"))


# Define number of drug classes started (numstart) and stopped on each date (numstop)

all_scripts_long <- all_scripts_long %>%
 group_by(patid, date) %>%
 mutate(numstart_class=sum(dstart_class, na.rm=TRUE),
     numstop_class=sum(dstop_class, na.rm=TRUE),
     numstart_substance=sum(dstart_substance, na.rm=TRUE),
     numstop_substance=sum(dstop_substance, na.rm=TRUE)) %>%
 ungroup() %>%
 analysis$cached("all_scripts_long", indexes=c("patid", "date"))


############################################################################################

# all_scripts table: 1 line per patid / date where script issued, with drug class and drug substance info in wide format
 
# Define drug classes and drug substances in dataset

# drugclasses <- sort(unlist(list((all_scripts_long %>% distinct(drug_class) %>% collect())$drug_class)))
# drugclasses
# "Acarbose" "DPP4"   "GIPGLP1" "Glinide" "GLP1"   "INS"   "MFN"   "SGLT2"  "SU"    "TZD" 

drugclasses <- c("Acarbose", "DPP4", "GIPGLP1", "Glinide", "GLP1", "INS", "MFN", "SGLT2", "SU", "TZD")

# drugsubstances <- sort(unlist(list((all_scripts_long %>% distinct(drug_substance) %>% collect())$drug_substance)))
# drugsubstances
# [1] "Acarbose"          "Albiglutide"         "Alogliptin"         
# [4] "Canagliflozin"        "Chlorpropamide"       "Dapagliflozin"       
# [7] "Dulaglutide"         "Empagliflozin"        "Ertugliflozin"       
# [10] "Exenatide"          "Exenatide prolonged-release" "Glibenclamide"       
# [13] "Gliclazide"         "Glimepiride"         "Glipizide"         
# [16] "Gliquidone"         "Glymidine"          "High-dose semaglutide"   
# [19] "Insulin"           "Linagliptin"         "Liraglutide"        
# [22] "Lixisenatide"        "Low-dose semaglutide"    "Metformin"         
# [25] "Nateglinide"         "Oral semaglutide"      "Pioglitazone"        
# [28] "Repaglinide"         "Rosiglitazone"        "Saxagliptin"        
# [31] "Semaglutide, dose unclear"  "Sitagliptin"         "Tirzepatide"        
# [34] "Tolazamide"         "Tolbutamide"         "Troglitazone"        
# [37] "Vildagliptin"
# No acetohexamide- 37/38 possible drug substances

drugsubstances <- c("Acarbose", "Albiglutide", "Alogliptin", "Canagliflozin", "Chlorpropamide", "Dapagliflozin", "Dulaglutide", "Empagliflozin", "Ertugliflozin", "Exenatide", "Exenatide prolonged-release", "Glibenclamide", "Gliclazide", "Glimepiride", "Glipizide", "Gliquidone", "Glymidine", "High-dose semaglutide", "Insulin", "Linagliptin", "Liraglutide", "Lixisenatide", "Low-dose semaglutide", "Metformin", "Nateglinide", "Oral semaglutide", "Pioglitazone", "Repaglinide", "Rosiglitazone", "Saxagliptin", "Semaglutide, dose unclear", "Sitagliptin", "Tirzepatide", "Tolazamide", "Tolbutamide", "Troglitazone", "Vildagliptin")


# Reshape all_scripts_long wide by drug class and drug substance - so 1 row per patid/date

all_scripts_class_wide <- all_scripts_long %>%
 pivot_wider(c(patid, date, numstart_class, numstop_class),
       names_from=drug_class,
       values_from=c(dstart_class, dstop_class),
       values_fill=list(dstart_class=FALSE, dstop_class=FALSE)) %>%
 analysis$cached("all_scripts_class_wide", indexes=c("patid", "date"))

#all_scripts_class_wide %>% count()
#155,411,996

all_scripts_substance_wide <- all_scripts_long %>%
 pivot_wider(c(patid, date, numstart_substance, numstop_substance),
       names_from=drug_substance,
       values_from=c(dstart_substance, dstop_substance),
       values_fill=list(dstart_substance=FALSE, dstop_substance=FALSE)) %>%
 analysis$cached("all_scripts_substance_wide", indexes=c("patid", "date"))

#all_scripts_substance_wide %>% count()
#155,411,996

all_scripts <- all_scripts_class_wide %>%
 inner_join(all_scripts_substance_wide, by=c("patid", "date")) %>%
 analysis$cached("all_scripts_interim_1", indexes=c("patid", "date"))

#all_scripts %>% count()
#155,411,996


# Use numstart and numstop to work out total number of drug classes patient is on at each date (numdrugs; they can be on a drug even if not prescribed on that date)
## Add numstop to numdrugs so that drug stopped is included in numdrugs count on the date it is stopped

all_scripts <- all_scripts %>%
 group_by(patid) %>%
 dbplyr::window_order(date) %>%
 mutate(cu_numstart_class=cumsum(numstart_class),
     cu_numstop_class=cumsum(numstop_class),
     numdrugs_class=cu_numstart_class-cu_numstop_class+numstop_class,
     cu_numstart_substance=cumsum(numstart_substance),
     cu_numstop_substance=cumsum(numstop_substance),
     numdrugs_substance=cu_numstart_substance-cu_numstop_substance+numstop_substance) %>%
 ungroup()


# Make variable for what combination of drugs patient is on at each date
## First make binary variables for each drug for whether patient was on the drug (whether or not prescribed) at each date
## When this was initially run with loops, it took a very long time (5-6 hours) as each iteration of the loop produces another temporary table - so have removed loop here and 2 loops in subsequent code

##NB: only 1 'Acarbose' variable cerated - for class and substance - could name them differently in the future

all_scripts <- all_scripts %>%
 group_by(patid) %>%
 dbplyr::window_order(date) %>%
 mutate(Acarbose=cumsum(dstart_class_Acarbose)>cumsum(dstop_class_Acarbose) | dstart_class_Acarbose==1 | dstop_class_Acarbose==1,
     DPP4=cumsum(dstart_class_DPP4)>cumsum(dstop_class_DPP4) | dstart_class_DPP4==1 | dstop_class_DPP4==1,
     GIPGLP1=cumsum(dstart_class_GIPGLP1)>cumsum(dstop_class_GIPGLP1) | dstart_class_GIPGLP1==1 | dstop_class_GIPGLP1==1,
     Glinide=cumsum(dstart_class_Glinide)>cumsum(dstop_class_Glinide) | dstart_class_Glinide==1 | dstop_class_Glinide==1,
     GLP1=cumsum(dstart_class_GLP1)>cumsum(dstop_class_GLP1) | dstart_class_GLP1==1 | dstop_class_GLP1==1,
     MFN=cumsum(dstart_class_MFN)>cumsum(dstop_class_MFN) | dstart_class_MFN==1 | dstop_class_MFN==1,
     SGLT2=cumsum(dstart_class_SGLT2)>cumsum(dstop_class_SGLT2) | dstart_class_SGLT2==1 | dstop_class_SGLT2==1,
     SU=cumsum(dstart_class_SU)>cumsum(dstop_class_SU) | dstart_class_SU==1 | dstop_class_SU==1,
     TZD=cumsum(dstart_class_TZD)>cumsum(dstop_class_TZD) | dstart_class_TZD==1 | dstop_class_TZD==1,
     INS=cumsum(dstart_class_INS)>cumsum(dstop_class_INS) | dstart_class_INS==1 | dstop_class_INS==1,
     
     `Acarbose`=cumsum(`dstart_substance_Acarbose`)>cumsum(`dstop_substance_Acarbose`) | `dstart_substance_Acarbose`==1 | `dstop_substance_Acarbose`==1,
     `Albiglutide`=cumsum(`dstart_substance_Albiglutide`)>cumsum(`dstop_substance_Albiglutide`) | `dstart_substance_Albiglutide`==1 | `dstop_substance_Albiglutide`==1,
     `Alogliptin`=cumsum(`dstart_substance_Alogliptin`)>cumsum(`dstop_substance_Alogliptin`) | `dstart_substance_Alogliptin`==1 | `dstop_substance_Alogliptin`==1,
     `Canagliflozin`=cumsum(`dstart_substance_Canagliflozin`)>cumsum(`dstop_substance_Canagliflozin`) | `dstart_substance_Canagliflozin`==1 | `dstop_substance_Canagliflozin`==1,
     `Chlorpropamide`=cumsum(`dstart_substance_Chlorpropamide`)>cumsum(`dstop_substance_Chlorpropamide`) | `dstart_substance_Chlorpropamide`==1 | `dstop_substance_Chlorpropamide`==1,
     `Dapagliflozin`=cumsum(`dstart_substance_Dapagliflozin`)>cumsum(`dstop_substance_Dapagliflozin`) | `dstart_substance_Dapagliflozin`==1 | `dstop_substance_Dapagliflozin`==1,
     `Dulaglutide`=cumsum(`dstart_substance_Dulaglutide`)>cumsum(`dstop_substance_Dulaglutide`) | `dstart_substance_Dulaglutide`==1 | `dstop_substance_Dulaglutide`==1,
     `Empagliflozin`=cumsum(`dstart_substance_Empagliflozin`)>cumsum(`dstop_substance_Empagliflozin`) | `dstart_substance_Empagliflozin`==1 | `dstop_substance_Empagliflozin`==1,
     `Ertugliflozin`=cumsum(`dstart_substance_Ertugliflozin`)>cumsum(`dstop_substance_Ertugliflozin`) | `dstart_substance_Ertugliflozin`==1 | `dstop_substance_Ertugliflozin`==1,
     `Exenatide`=cumsum(`dstart_substance_Exenatide`)>cumsum(`dstop_substance_Exenatide`) | `dstart_substance_Exenatide`==1 | `dstop_substance_Exenatide`==1,
     `Exenatide prolonged-release`=cumsum(`dstart_substance_Exenatide prolonged-release`)>cumsum(`dstop_substance_Exenatide prolonged-release`) | `dstart_substance_Exenatide prolonged-release`==1 | `dstop_substance_Exenatide prolonged-release`==1,
     `Glibenclamide`=cumsum(`dstart_substance_Glibenclamide`)>cumsum(`dstop_substance_Glibenclamide`) | `dstart_substance_Glibenclamide`==1 | `dstop_substance_Glibenclamide`==1,
     `Gliclazide`=cumsum(`dstart_substance_Gliclazide`)>cumsum(`dstop_substance_Gliclazide`) | `dstart_substance_Gliclazide`==1 | `dstop_substance_Gliclazide`==1,
     `Glimepiride`=cumsum(`dstart_substance_Glimepiride`)>cumsum(`dstop_substance_Glimepiride`) | `dstart_substance_Glimepiride`==1 | `dstop_substance_Glimepiride`==1,
     `Glipizide`=cumsum(`dstart_substance_Glipizide`)>cumsum(`dstop_substance_Glipizide`) | `dstart_substance_Glipizide`==1 | `dstop_substance_Glipizide`==1,
     `Gliquidone`=cumsum(`dstart_substance_Gliquidone`)>cumsum(`dstop_substance_Gliquidone`) | `dstart_substance_Gliquidone`==1 | `dstop_substance_Gliquidone`==1,
     `Glymidine`=cumsum(`dstart_substance_Glymidine`)>cumsum(`dstop_substance_Glymidine`) | `dstart_substance_Glymidine`==1 | `dstop_substance_Glymidine`==1,
     `High-dose semaglutide`=cumsum(`dstart_substance_High-dose semaglutide`)>cumsum(`dstop_substance_High-dose semaglutide`) | `dstart_substance_High-dose semaglutide`==1 | `dstop_substance_High-dose semaglutide`==1,
     `Insulin`=cumsum(`dstart_substance_Insulin`)>cumsum(`dstop_substance_Insulin`) | `dstart_substance_Insulin`==1 | `dstop_substance_Insulin`==1,
     `Linagliptin`=cumsum(`dstart_substance_Linagliptin`)>cumsum(`dstop_substance_Linagliptin`) | `dstart_substance_Linagliptin`==1 | `dstop_substance_Linagliptin`==1,
     `Liraglutide`=cumsum(`dstart_substance_Liraglutide`)>cumsum(`dstop_substance_Liraglutide`) | `dstart_substance_Liraglutide`==1 | `dstop_substance_Liraglutide`==1,
     `Lixisenatide`=cumsum(`dstart_substance_Lixisenatide`)>cumsum(`dstop_substance_Lixisenatide`) | `dstart_substance_Lixisenatide`==1 | `dstop_substance_Lixisenatide`==1,
     `Low-dose semaglutide`=cumsum(`dstart_substance_Low-dose semaglutide`)>cumsum(`dstop_substance_Low-dose semaglutide`) | `dstart_substance_Low-dose semaglutide`==1 | `dstop_substance_Low-dose semaglutide`==1,
     `Metformin`=cumsum(`dstart_substance_Metformin`)>cumsum(`dstop_substance_Metformin`) | `dstart_substance_Metformin`==1 | `dstop_substance_Metformin`==1,
     `Nateglinide`=cumsum(`dstart_substance_Nateglinide`)>cumsum(`dstop_substance_Nateglinide`) | `dstart_substance_Nateglinide`==1 | `dstop_substance_Nateglinide`==1,
     `Oral semaglutide`=cumsum(`dstart_substance_Oral semaglutide`)>cumsum(`dstop_substance_Oral semaglutide`) | `dstart_substance_Oral semaglutide`==1 | `dstop_substance_Oral semaglutide`==1,
     `Pioglitazone`=cumsum(`dstart_substance_Pioglitazone`)>cumsum(`dstop_substance_Pioglitazone`) | `dstart_substance_Pioglitazone`==1 | `dstop_substance_Pioglitazone`==1,
     `Repaglinide`=cumsum(`dstart_substance_Repaglinide`)>cumsum(`dstop_substance_Repaglinide`) | `dstart_substance_Repaglinide`==1 | `dstop_substance_Repaglinide`==1,
     `Rosiglitazone`=cumsum(`dstart_substance_Rosiglitazone`)>cumsum(`dstop_substance_Rosiglitazone`) | `dstart_substance_Rosiglitazone`==1 | `dstop_substance_Rosiglitazone`==1,
     `Saxagliptin`=cumsum(`dstart_substance_Saxagliptin`)>cumsum(`dstop_substance_Saxagliptin`) | `dstart_substance_Saxagliptin`==1 | `dstop_substance_Saxagliptin`==1,
     `Semaglutide, dose unclear`=cumsum(`dstart_substance_Semaglutide, dose unclear`)>cumsum(`dstop_substance_Semaglutide, dose unclear`) | `dstart_substance_Semaglutide, dose unclear`==1 | `dstop_substance_Semaglutide, dose unclear`==1,
     `Sitagliptin`=cumsum(`dstart_substance_Sitagliptin`)>cumsum(`dstop_substance_Sitagliptin`) | `dstart_substance_Sitagliptin`==1 | `dstop_substance_Sitagliptin`==1,
     `Tirzepatide`=cumsum(`dstart_substance_Tirzepatide`)>cumsum(`dstop_substance_Tirzepatide`) | `dstart_substance_Tirzepatide`==1 | `dstop_substance_Tirzepatide`==1,
     `Tolazamide`=cumsum(`dstart_substance_Tolazamide`)>cumsum(`dstop_substance_Tolazamide`) | `dstart_substance_Tolazamide`==1 | `dstop_substance_Tolazamide`==1,
     `Tolbutamide`=cumsum(`dstart_substance_Tolbutamide`)>cumsum(`dstop_substance_Tolbutamide`) | `dstart_substance_Tolbutamide`==1 | `dstop_substance_Tolbutamide`==1,
     `Troglitazone`=cumsum(`dstart_substance_Troglitazone`)>cumsum(`dstop_substance_Troglitazone`) | `dstart_substance_Troglitazone`==1 | `dstop_substance_Troglitazone`==1,
     `Vildagliptin`=cumsum(`dstart_substance_Vildagliptin`)>cumsum(`dstop_substance_Vildagliptin`) | `dstart_substance_Vildagliptin`==1 | `dstop_substance_Vildagliptin`==1) %>%
 ungroup() %>% 
 analysis$cached("all_scripts_interim_2", indexes=c("patid", "date"))


## Use binary drug class columns to make single 'drugcombo' column with the names of all the drug classes patient is on at each date
## Previous step ran really slowly (5-6 hours) - each iteration of the loop produces another temporary table - so have removed 2 x loops here

all_scripts <- all_scripts %>%
 select(-c(starts_with("dstart"), starts_with("dstop"))) %>%
 mutate(drug_class_combo=paste0(ifelse(Acarbose==1, "Acarbose_", NA),
                 ifelse(DPP4==1, "DPP4_", NA),
                 ifelse(GIPGLP1==1, "GIPGLP1_", NA),
                 ifelse(Glinide==1, "Glinide_", NA),
                 ifelse(GLP1==1, "GLP1_", NA),
                 ifelse(MFN==1, "MFN_", NA),
                 ifelse(SGLT2==1, "SGLT2_", NA),
                 ifelse(SU==1, "SU_", NA),
                 ifelse(TZD==1, "TZD_", NA),
                 ifelse(INS==1, "INS_", NA)),
     drug_class_combo=ifelse(str_sub(drug_class_combo, -1, -1)=="_", str_sub(drug_class_combo, 1, -2), drug_class_combo),
     drug_substance_combo=paste0(ifelse(`Acarbose`==1, "Acarbose_", NA),
                   ifelse(`Albiglutide`==1, "Albiglutide_", NA),
                   ifelse(`Alogliptin`==1, "Alogliptin_", NA),
                   ifelse(`Canagliflozin`==1, "Canagliflozin_", NA),
                   ifelse(`Chlorpropamide`==1, "Chlorpropamide_", NA),
                   ifelse(`Dapagliflozin`==1, "Dapagliflozin_", NA),
                   ifelse(`Dulaglutide`==1, "Dulaglutide_", NA),
                   ifelse(`Empagliflozin`==1, "Empagliflozin_", NA),
                   ifelse(`Ertugliflozin`==1, "Ertugliflozin_", NA),
                   ifelse(`Exenatide`==1, "Exenatide_", NA),
                   ifelse(`Exenatide prolonged-release`==1, "Exenatide prolonged-release_", NA),
                   ifelse(`Glibenclamide`==1, "Glibenclamide_", NA),
                   ifelse(`Gliclazide`==1, "Gliclazide_", NA),
                   ifelse(`Glimepiride`==1, "Glimepiride_", NA),
                   ifelse(`Glipizide`==1, "Glipizide_", NA),
                   ifelse(`Gliquidone`==1, "Gliquidone_", NA),
                   ifelse(`Glymidine`==1, "Glymidine_", NA),
                   ifelse(`High-dose semaglutide`==1, "High-dose semaglutide_", NA),
                   ifelse(`Insulin`==1, "Insulin_", NA),
                   ifelse(`Linagliptin`==1, "Linagliptin_", NA),
                   ifelse(`Liraglutide`==1, "Liraglutide_", NA),
                   ifelse(`Lixisenatide`==1, "Lixisenatide_", NA),
                   ifelse(`Low-dose semaglutide`==1, "Low-dose semaglutide_", NA),
                   ifelse(`Metformin`==1, "Metformin_", NA),
                   ifelse(`Nateglinide`==1, "Nateglinide_", NA),
                   ifelse(`Oral semaglutide`==1, "Oral semaglutide_", NA),
                   ifelse(`Pioglitazone`==1, "Pioglitazone_", NA),
                   ifelse(`Repaglinide`==1, "Repaglinide_", NA),
                   ifelse(`Rosiglitazone`==1, "Rosiglitazone_", NA),
                   ifelse(`Saxagliptin`==1, "Saxagliptin_", NA),
                   ifelse(`Semaglutide, dose unclear`==1, "Semaglutide, dose unclear_", NA),
                   ifelse(`Sitagliptin`==1, "Sitagliptin_", NA),
                   ifelse(`Tirzepatide`==1, "Tirzepatide_", NA),
                   ifelse(`Tolazamide`==1, "Tolazamide_", NA),
                   ifelse(`Tolbutamide`==1, "Tolbutamide_", NA),
                   ifelse(`Troglitazone`==1, "Troglitazone_", NA),
                   ifelse(`Vildagliptin`==1, "Vildagliptin_", NA)),
     drug_substance_combo=ifelse(str_sub(drug_substance_combo, -1, -1)=="_", str_sub(drug_substance_combo, 1, -2), drug_substance_combo))


# Recalculate numdrugs (number of different drug classes patient is on at each date) and check it matches earlier calculation

all_scripts <- all_scripts %>%
 mutate(numdrugs_class2=Acarbose + DPP4 + GIPGLP1 + Glinide + GLP1 + MFN + SGLT2 + SU + TZD + INS,
     numdrugs_substance2=`Acarbose` + `Albiglutide` + `Alogliptin` + `Canagliflozin` + `Chlorpropamide` + `Dapagliflozin` + `Dulaglutide` + `Empagliflozin` + `Ertugliflozin` + `Exenatide` + `Exenatide prolonged-release` + `Glibenclamide` + `Gliclazide` + `Glimepiride` + `Glipizide` + `Gliquidone` + `Glymidine` + `High-dose semaglutide` + `Insulin` + `Linagliptin` + `Liraglutide` + `Lixisenatide` + `Low-dose semaglutide` + `Metformin` + `Nateglinide` + `Oral semaglutide` + `Pioglitazone` + `Repaglinide` + `Rosiglitazone` + `Saxagliptin` + `Semaglutide, dose unclear` + `Sitagliptin` + `Tirzepatide` + `Tolazamide` + `Tolbutamide` + `Troglitazone` + `Vildagliptin`) %>%
 analysis$cached("all_scripts_interim_3", indexes=c("patid", "date"))

#all_scripts %>% filter(numdrugs_class!=numdrugs_class2 | is.na(numdrugs_class) | is.na(numdrugs_class2)) %>% count()
# 0 - perfect

#all_scripts %>% filter(numdrugs_substance!=numdrugs_substance2 | is.na(numdrugs_substance) | is.na(numdrugs_substance2)) %>% count()
# 0 - perfect


# Define whether date is start or stop for each drug combination
## Coded differently to drug classes as patient can only be on one combination at once 
## Find time from previous script (dcprevuse) and to next script (dncextuse) for same person and same drug combo
## If previous script is for a different drug combo or no previous script, define as start date (dcstart=1)
## If next script is for a different drug combo or no next script, define as stop date (dcstop=1)

all_scripts <- all_scripts %>%
 group_by(patid, drug_class_combo) %>%
 dbplyr::window_order(date) %>%
 mutate(dcnextuse_class=datediff(lead(date), date),
     dcprevuse_class=datediff(date, lag(date))) %>%
 ungroup() %>%
 analysis$cached("all_scripts_interim_4", indexes=c("patid", "date"))
 

## Have to do in 2 parts otherwise crashes

all_scripts_a <- all_scripts %>% 
 filter(patid<4000000000000) %>%
 group_by(patid, drug_substance_combo) %>%
 dbplyr::window_order(date) %>%
 mutate(dcnextuse_substance=datediff(lead(date), date),
     dcprevuse_substance=datediff(date, lag(date))) %>%
 ungroup() %>%
 analysis$cached("all_scripts_interim_5a", indexes=c("patid", "date"))
 
all_scripts_b <- all_scripts %>% 
 filter(patid>=4000000000000) %>%
 group_by(patid, drug_substance_combo) %>%
 dbplyr::window_order(date) %>%
 mutate(dcnextuse_substance=datediff(lead(date), date),
     dcprevuse_substance=datediff(date, lag(date))) %>%
 ungroup() %>%
 analysis$cached("all_scripts_interim_5b", indexes=c("patid", "date"))


all_scripts <- all_scripts_a %>%
 union_all(all_scripts_b) %>%
 group_by(patid) %>%
 dbplyr::window_order(date) %>%
 mutate(dcstart_class=drug_class_combo!=lag(drug_class_combo) | is.na(dcprevuse_class),
     dcstop_class=drug_class_combo!=lead(drug_class_combo) | is.na(dcnextuse_class),
     dcstart_substance=drug_substance_combo!=lag(drug_substance_combo) | is.na(dcprevuse_substance),
     dcstop_substance=drug_substance_combo!=lead(drug_substance_combo) | is.na(dcnextuse_substance)) %>%
 ungroup() %>%
 analysis$cached("all_scripts_interim_6", indexes=c("patid", "date"))
 
#all_scripts %>% count()
#155,411,996


# Add 'gaps': defined as break of >6 months (183 days) in prescribing of combination
## Update start and stop dates based on these

all_scripts <- all_scripts %>%
 group_by(patid) %>%
 dbplyr::window_order(date) %>%
 mutate(stopgap_class=ifelse(dcnextuse_class>183 & drug_class_combo==lead(drug_class_combo), 1L, NA),
     startgap_class=ifelse((dcprevuse_class>183 | is.na(dcprevuse_class)), 1L, NA),
     dcstop_class=ifelse(!is.na(stopgap_class) & stopgap_class==1 & dcstop_class==0, 1L, dcstop_class),
     dcstart_class=ifelse(!is.na(startgap_class) & startgap_class==1 & dcstart_class==0, 1L, dcstart_class),
     
     stopgap_substance=ifelse(dcnextuse_substance>183 & drug_substance_combo==lead(drug_substance_combo), 1L, NA),
     startgap_substance=ifelse((dcprevuse_substance>183 | is.na(dcprevuse_substance)), 1L, NA),
     dcstop_substance=ifelse(!is.na(stopgap_substance) & stopgap_substance==1 & dcstop_substance==0, 1L, dcstop_substance),
     dcstart_substance=ifelse(!is.na(startgap_substance) & startgap_substance==1 & dcstart_substance==0, 1L, dcstart_substance)) %>%
 ungroup()


# Add in time to last prescription date for each patient (any drug class)

all_scripts <- all_scripts %>%
 group_by(patid) %>%
 mutate(timetolastpx=datediff(max(date, na.rm=TRUE), date)) %>%
 ungroup() %>%
 analysis$cached("all_scripts", indexes=c("patid", "date"))

#all_scripts %>% count()
#155,441,996


############################################################################################

# drug_class_start_stop = 1 line per patid / drug class instance (continuous period of drug use)
## Below section is identical to this but uses drug substance

# Just keep dates where a drug is started or stopped
## Pull out start and stop dates on rows where dstart==1
## Each row either has both start and stop date, or start on one date and next date for same patid and drug class will be stop date

drug_class_start_stop <- all_scripts_long %>%
 filter(dstart_class==1 | dstop_class==1) %>%
 group_by(patid, drug_class) %>%
 dbplyr::window_order(date) %>%
 mutate(dstartdate_class=if_else(dstart_class==1, date, as.Date(NA)),
     dstopdate_class=if_else(dstart_class==1 & dstop_class==1, date, 
              if_else(dstart_class==1 & dstop_class==0, lead(date), as.Date(NA)))) %>%
 ungroup() %>%
 analysis$cached("drug_class_start_stop_interim_1", indexes=c("patid", "dstart_class"))


# Just keep rows where dstart==1 - 1 row per drug class instance, and only keep variables which apply to whole instance, not those relating to specific scripts within the instance

drug_class_start_stop <- drug_class_start_stop %>%
 filter(dstart_class==1) %>%
 select(patid, drug_class, dstartdate_class, dstopdate_class) %>%
 analysis$cached("drug_class_start_stop_interim_2", indexes=c("patid", "dstartdate_class"))

#drug_class_start_stop %>% count()
#5,995,512


# Add drug order count within each patid: how many periods of medication have they had
## If multiple meds started on same day, use minimum for both/all drugs

drug_class_start_stop <- drug_class_start_stop %>%
 group_by(patid) %>%
 dbplyr::window_order(dstartdate_class) %>%
 mutate(drug_order=row_number()) %>%
 ungroup() %>%
 group_by(patid, dstartdate_class) %>%
 mutate(drug_order=min(drug_order, na.rm=TRUE)) %>%  #means meds started on same day have same drug_order
 ungroup() %>%
 analysis$cached("drug_class_start_stop_interim_3", indexes=c("patid", "drug_class", "dstartdate_class"))
      

# Add drug instance count for each patid / drug class instance e.g. if several periods of MFN usage, these should be labelled 1, 2 etc. based on start date

drug_class_start_stop <- drug_class_start_stop %>%
 group_by(patid, drug_class) %>%
 dbplyr::window_order(dstartdate_class) %>%
 mutate(drug_instance=row_number()) %>%
 ungroup() %>%
 analysis$cached("drug_class_start_stop_interim_4", indexes=c("patid", "drug_class", "dstartdate_class"))


# Add drug line for each patid / drug class: on first usage of this drug, how many previous distinct drug classes had been used + 1 
## If multiple meds started on same day, use minimum for both/all drugs

drug_line <- drug_class_start_stop %>%
 filter(drug_instance==1) %>%  # same as just keeping 1 row per patid/ drug class with minimum start date
 group_by(patid) %>%
 dbplyr::window_order(dstartdate_class) %>%
 mutate(drugline_all=row_number()) %>%
 ungroup() %>%
 
 group_by(patid, dstartdate_class) %>%
 mutate(drugline_all=min(drugline_all, na.rm=TRUE)) %>%
 ungroup() %>%
 
 select(patid, drug_class, drugline_all) 

drug_class_start_stop <- drug_class_start_stop %>%
 inner_join(drug_line, by=c("patid", "drug_class")) %>%
 analysis$cached("drug_class_start_stop", indexes=c("patid", "dstartdate_class", "drug_class", "drug_instance"))

#drug_class_start_stop %>% count()
#5,990,512


############################################################################################

# drug_substance_start_stop = 1 line per patid / drug substance instance (continuous period of drug use)
# Identical to above code - except uses substance rather than class and doesn't calculate drug_order, drug_instance and drug_line

# First, add in number of prescriptions in drug substance period (actually number of days as duplicates for patid, substance and date removed earlier)

drug_substance_start_stop <- all_scripts_long %>%
 group_by(patid, drug_substance) %>%
 dbplyr::window_order(date) %>%
 mutate(drug_substance_starts=cumsum(dstart_substance==1)) %>%
 ungroup() %>%
 group_by(patid, drug_substance, drug_substance_starts) %>%
 mutate(scripts_in_substance_period=n()) %>%
 ungroup() %>%
 analysis$cached("drug_substance_start_stop_interim_1", indexes=c("patid", "date", "dstart_substance", "dstop_substance"))


# Just keep dates where a drug is started or stopped
## Pull out start and stop dates on rows where dstart==1
## Each row either has both start and stop date, or start on one date and next date for same patid and drug class will be stop date

drug_substance_start_stop <- drug_substance_start_stop %>%
 filter(dstart_substance==1 | dstop_substance==1) %>%
 group_by(patid, drug_substance) %>%
 dbplyr::window_order(date) %>%
 mutate(dstartdate_substance=if_else(dstart_substance==1, date, as.Date(NA)),
     dstopdate_substance=if_else(dstart_substance==1 & dstop_substance==1, date, 
              if_else(dstart_substance==1 & dstop_substance==0, lead(date), as.Date(NA)))) %>%
 ungroup() %>%
 analysis$cached("drug_substance_start_stop_interim_2", indexes=c("patid", "dstartdate_substance"))


# Just keep rows where dstart==1 - 1 row per drug class instance, and only keep variables which apply to whole instance, not those relating to specific scripts within the instance

drug_substance_start_stop <- drug_substance_start_stop %>%
 filter(dstart_substance==1) %>%
 select(patid, drug_class, drug_substance, dstartdate_substance, dstopdate_substance, scripts_in_substance_period) %>%
 analysis$cached("drug_substance_start_stop", indexes=c("patid", "dstartdate_substance", "drug_substance"))

#drug_substance_start_stop %>% count()
#6,244,052


############################################################################################

# Combine drug_start_stop tables
## Copy down class-specific variables (drug_order, drug_instance, drugline_all) to all drug substance starts within this drug class period

drug_start_stop <- drug_substance_start_stop %>%
  left_join(drug_class_start_stop, by=c("patid", "drug_class", c("dstartdate_substance"="dstartdate_class"))) %>%
  mutate(drug_class_start=ifelse(!is.na(dstopdate_class), 1L, 0L)) %>%
  group_by(patid, drug_class) %>%
  dbplyr::window_order(dstartdate_substance) %>%
  mutate(drug_class_starts=cumsum(drug_class_start==1)) %>%
  dbplyr::window_order() %>%
  ungroup() %>%
  group_by(patid, drug_class, drug_class_starts) %>%
  mutate(drug_order=max(drug_order, na.rm=TRUE),
         drug_instance=max(drug_instance, na.rm=TRUE),
         drugline_all=max(drugline_all, na.rm=TRUE),
         dstopdate_class=max(dstopdate_class, na.rm=TRUE)) %>%
  ungroup() %>%
  select(patid, dstartdate=dstartdate_substance, drug_class_start, drug_class, dstopdate_class, drug_order, drug_instance, drugline_all, drug_substance, dstopdate_substance, scripts_in_substance_period) %>%
  analysis$cached("drug_start_stop_interim_1", indexes=c("patid", "dstartdate", "drug_class", "drug_substance"))
  


## Define different substance periods within same drug class period (patid - drug_class - drug_order defines unique drug class period)
# 0 - only substance in drug class period (NB: if full drug class period is 1 script only, substance_status will still be 0)
# 1 - multiple substances within drug class period, this one covers full drug class period (NB: if full drug class period is 1 script only, substance_status will be 4 not 1)
# 2 - multiple substance within drug class period, this one has >1 script and is started at start of drug class period but stops before end of drug class period
# 3 - multiple substance within drug class period, this one has >1 script and is during drug class period
# 4 - multiple substances within drug class period, this one has only 1 script (can be at beginning or during of drug class period). NB: if full drug class period is 1 script only, subtance_status will be 4 not 1

# 1a-c, 2a-c, 3a-c, 4a-c if multiple substances meet definition: ordered by drug substance alphabetically

drug_start_stop <- drug_start_stop %>%
  group_by(patid, drug_class, drug_order) %>%
  mutate(total_substance_count=n()) %>%
  ungroup() %>%
  mutate(substance_status=ifelse(total_substance_count==1, 0L,
                                 ifelse(scripts_in_substance_period==1, 4L,
                                        ifelse(total_substance_count>1 & scripts_in_substance_period>1 & drug_class_start==1 & dstopdate_substance==dstopdate_class, 1L,
                                               ifelse(total_substance_count>1 & scripts_in_substance_period>1 & drug_class_start==1 & dstopdate_substance<dstopdate_class, 2L,
                                                      ifelse(total_substance_count>1 & scripts_in_substance_period>1 & drug_class_start==0, 3L, NA)))))) %>%
  
  group_by(patid, drug_class, drug_order, substance_status) %>%
  dbplyr::window_order(drug_substance) %>%
  mutate(substance_status_count=n(),
         substance_order=row_number()) %>%
  dbplyr::window_order() %>%
  ungroup() %>%
  
  mutate(substance_status=ifelse(substance_status_count==1, substance_status,
                                  ifelse(substance_status_count>1 & substance_order==1, paste0(substance_status, "a"),
                                         ifelse(substance_status_count>1 & substance_order==2, paste0(substance_status, "b"),
                                                ifelse(substance_status_count>1 & substance_order==3, paste0(substance_status, "c"),
                                                       ifelse(substance_status_count>1 & substance_order==4, paste0(substance_status, "d"),
                                                              ifelse(substance_status_count>1 & substance_order==5, paste0(substance_status, "e"),
                                                                     ifelse(substance_status_count>1 & substance_order==6, paste0(substance_status, "f"),
                                                                            ifelse(substance_status_count>1 & substance_order==7, paste0(substance_status, "g"),
                                                                                   ifelse(substance_status_count>1 & substance_order==8, paste0(substance_status, "h"),
                                                                                          ifelse(substance_status_count>1 & substance_order==9, paste0(substance_status, "i"),
                                                                                                 ifelse(substance_status_count>1 & substance_order==10, paste0(substance_status, "j"), NA)))))))))))) %>%
    
    select(patid, dstartdate, drug_class_start, drug_class, dstopdate_class, drug_order, drug_instance, drugline_all, drug_substance, substance_status, dstopdate_substance, scripts_in_substance_period) %>%
  
  analysis$cached("drug_start_stop", indexes=c("patid", "dstartdate", "drug_class", "drug_substance"))
  

drug_start_stop %>% count()
#6,244,052


############################################################################################

# combo_class_start_stop = 1 line per patid / drug combo instance (continuous period of drug combo use) BASED ON DRUG CLASSES
# Next section of code is similar, but based on drug substances

# Similar process to that for drug classes above:
## Just keep dates where a drug is started or stopped
## Pull out start and stop dates on rows where dcstart==1
## Each row either has both start and stop date, or start on one date and next date for same patid will be stop date (as can only be on one drug combo at once)

combo_class_start_stop <- all_scripts %>%
 filter(dcstart_class==1 | dcstop_class==1) %>%
 group_by(patid) %>%
 dbplyr::window_order(date) %>%
 mutate(dcstartdate=if_else(dcstart_class==1, date, as.Date(NA)),
     dcstopdate=if_else(dcstart_class==1 & dcstop_class==1, date, 
              if_else(dcstart_class==1 & dcstop_class==0, lead(date), as.Date(NA)))) %>%
 ungroup() %>%
 analysis$cached("combo_class_start_stop_interim_1", indexes=c("patid", "dcstart_class"))


# Just keep rows where dcstart==1 - 1 row per drug combo instance, and only keep variables which apply to whole instance

combo_class_start_stop <- combo_class_start_stop %>%
 filter(dcstart_class==1) %>%
 select(patid, drug_class_combo, numdrugs_class, dcstartdate, dcstopdate, Acarbose, DPP4, GIPGLP1, Glinide, GLP1, INS, MFN, SGLT2, SU, TZD) %>%
 analysis$cached("combo_class_start_stop_interim_2", indexes=c("patid", "dcstartdate"))

#combo_class_start_stop %>% count()
#7,207,116


# Add drugcomborder count within each patid: how many periods of medication have they had
## Also add 'nextdcdate': date next combination started (use stop date if last combination before end of prescriptions)

combo_class_start_stop <- combo_class_start_stop %>%
 group_by(patid) %>%
 dbplyr::window_order(dcstartdate) %>%
 mutate(drugcomboorder=row_number(),
     nextdcdate=if_else(is.na(lead(dcstartdate)), dcstopdate, lead(dcstartdate))) %>%
 ungroup() %>%
 analysis$cached("combo_class_start_stop_interim_3", indexes=c("patid", "dcstartdate"))


# Define what current and next drug combination represents in terms of adding/removing/swapping

combo_class_start_stop <- combo_class_start_stop %>%
 mutate(add=0L,
     adddrug=NA,
     rem=0L,
     remdrug=NA,
     nextadd=0L,
     nextadddrug=NA,
     nextrem=0L,
     nextremdrug=NA
     )

for (i in drugclasses) {
 
 drug_col <- as.symbol(i)
 
 combo_class_start_stop <- combo_class_start_stop %>%
  group_by(patid) %>%
  dbplyr::window_order(drugcomboorder) %>%
  mutate(add=ifelse(drug_col==1 & !is.na(lag(drug_col)) & lag(drug_col)==0, add+1L, add),
      adddrug=ifelse(drug_col==1 & !is.na(lag(drug_col)) & lag(drug_col)==0,
             ifelse(is.na(adddrug), i, paste(adddrug, "&", i)), adddrug),
      
      rem=ifelse(drug_col==0 & !is.na(lag(drug_col)) & lag(drug_col)==1, rem+1L, rem),
      remdrug=ifelse(drug_col==0 & !is.na(lag(drug_col)) & lag(drug_col)==1, ifelse(is.na(remdrug), i, paste(remdrug, "&", i)), remdrug),
      
      nextrem=ifelse(drug_col==1 & !is.na(lead(drug_col)) & lead(drug_col)==0, nextrem+1L, nextrem),
      nextremdrug=ifelse(drug_col==1 & !is.na(lead(drug_col)) & lead(drug_col)==0, ifelse(is.na(nextremdrug), i, paste(nextremdrug, "&", i)), nextremdrug),
      
      nextadd=ifelse(drug_col==0 & !is.na(lead(drug_col)) & lead(drug_col)==1, nextadd+1L, nextadd),
      nextadddrug=ifelse(drug_col==0 & !is.na(lead(drug_col)) & lead(drug_col)==1, ifelse(is.na(nextadddrug), i, paste(nextadddrug, "&", i)), nextadddrug)) %>%
  ungroup()
}

combo_class_start_stop <- combo_class_start_stop %>% analysis$cached("combo_class_start_stop_interim_4", indexes=c("patid", "dcstartdate"))


combo_class_start_stop <- combo_class_start_stop %>%
 
 mutate(swap=add>=1 & rem>=1,
     nextswap=nextadd>=1 & nextrem>=1,
     
     drugchange=case_when(
  add>=1 & rem==0 ~ "add",
  add==0 & rem>=1 ~ "remove",
  add>=1 & rem>=1 ~ "swap",
  add==0 & rem==0 & drugcomboorder==1 ~ "start of px",
  add==0 & rem==0 & drugcomboorder!=1 ~ "stop - break"),
  
  nextdrugchange=case_when(
   nextadd>=1 & nextrem==0 ~ "add",
   nextadd==0 & nextrem>=1 ~ "remove",
   nextadd>=1 & nextrem>=1 ~ "swap",
   nextadd==0 & nextrem==0 & nextdcdate!=dcstopdate ~ "stop - break",
   nextadd==0 & nextrem==0 & nextdcdate==dcstopdate ~ "stop - end of px")) %>%
 
 analysis$cached("combo_class_start_stop_interim_5", indexes=c("patid", "dcstartdate"))



# Add date of next drug combination (if last combination or before break, use stop date of current combination), date when a different drug class added or removed, and date when previous combination first prescribed

combo_class_start_stop <- combo_class_start_stop %>%
 group_by(patid) %>%
 dbplyr::window_order(dcstartdate) %>%
 mutate(datechange_class=ifelse(is.na(lead(dcstartdate)) | datediff(lead(dcstartdate), dcstopdate)>183, dcstopdate, lead(dcstartdate)),
     dateaddrem_class=ifelse(is.na(lead(dcstartdate)), NA, lead(dcstartdate)),
     dateprevcombo_class=lag(dcstartdate)) %>%
 ungroup()


# Add variable to indicate whether multiple drug classes started on the same day, plus timetochange, timetoaddrem and timeprevcombo variables

combo_class_start_stop <- combo_class_start_stop %>%
 mutate(multi_drug_start_class=ifelse(add>1 | (drugcomboorder==1 & numdrugs_class>1), 1L, 0L),
        timetochange_class=datediff(datechange_class, dcstartdate),
        timetoaddrem_class=datediff(dateaddrem_class, dcstartdate),
        timeprevcombo_class=datediff(dcstartdate, dateprevcombo_class)) %>% 
 analysis$cached("combo_class_start_stop", indexes=c("patid", "dcstartdate"))

#combo_class_start_stop %>% count()
#7,207,116


############################################################################################

# combo_substance_start_stop = 1 line per patid / drug combo instance (continuous period of drug combo use) BASED ON DRUG SUBSTANCES
# Previous section of code is similar, but based on drug substances

# Similar process to that for drug classes above:
## Just keep dates where a drug is started or stopped
## Pull out start and stop dates on rows where dcstart==1
## Each row either has both start and stop date, or start on one date and next date for same patid will be stop date (as can only be on one drug combo at once)

combo_substance_start_stop <- all_scripts %>%
 filter(dcstart_substance==1 | dcstop_substance==1) %>%
 group_by(patid) %>%
 dbplyr::window_order(date) %>%
 mutate(dcstartdate=if_else(dcstart_substance==1, date, as.Date(NA)),
     dcstopdate=if_else(dcstart_substance==1 & dcstop_substance==1, date, 
              if_else(dcstart_substance==1 & dcstop_substance==0, lead(date), as.Date(NA)))) %>%
 ungroup() %>%
 analysis$cached("combo_substance_start_stop_interim_1", indexes=c("patid", "dcstart_substance"))


# Just keep rows where dcstart==1 - 1 row per drug combo instance, and only keep variables which apply to whole instance

combo_substance_start_stop <- combo_substance_start_stop %>%
 filter(dcstart_substance==1) %>%
 select(patid, drug_substance_combo, numdrugs_substance, dcstartdate, dcstopdate, all_of(drugclasses), all_of(drugsubstances)) %>%
 analysis$cached("combo_substance_start_stop_interim_2", indexes=c("patid", "dcstartdate"))

#combo_substance_start_stop %>% count()
#7,523,780


# Add drugcomborder count within each patid: how many periods of medication have they had
## Also add 'nextdcdate': date next combination started (use stop date if last combination before end of prescriptions)

combo_substance_start_stop <- combo_substance_start_stop %>%
 group_by(patid) %>%
 dbplyr::window_order(dcstartdate) %>%
 mutate(drugcomboorder=row_number(),
     nextdcdate=if_else(is.na(lead(dcstartdate)), dcstopdate, lead(dcstartdate))) %>%
 ungroup() %>%
 analysis$cached("combo_substance_start_stop_interim_3", indexes=c("patid", "dcstartdate"))


# Define what current and next drug combination represents in terms of adding/removing/swapping

combo_substance_start_stop <- combo_substance_start_stop %>%
 mutate(add=0L,
     adddrug=NA,
     rem=0L,
     remdrug=NA,
     nextadd=0L,
     nextadddrug=NA,
     nextrem=0L,
     nextremdrug=NA
 )

for (i in drugsubstances) {
 
 drug_col <- as.symbol(i)
 
 combo_substance_start_stop <- combo_substance_start_stop %>%
  group_by(patid) %>%
  dbplyr::window_order(drugcomboorder) %>%
  mutate(add=ifelse(drug_col==1 & !is.na(lag(drug_col)) & lag(drug_col)==0, add+1L, add),
      adddrug=ifelse(drug_col==1 & !is.na(lag(drug_col)) & lag(drug_col)==0,
             ifelse(is.na(adddrug), i, paste(adddrug, "&", i)), adddrug),
      
      rem=ifelse(drug_col==0 & !is.na(lag(drug_col)) & lag(drug_col)==1, rem+1L, rem),
      remdrug=ifelse(drug_col==0 & !is.na(lag(drug_col)) & lag(drug_col)==1, ifelse(is.na(remdrug), i, paste(remdrug, "&", i)), remdrug),
      
      nextrem=ifelse(drug_col==1 & !is.na(lead(drug_col)) & lead(drug_col)==0, nextrem+1L, nextrem),
      nextremdrug=ifelse(drug_col==1 & !is.na(lead(drug_col)) & lead(drug_col)==0, ifelse(is.na(nextremdrug), i, paste(nextremdrug, "&", i)), nextremdrug),
      
      nextadd=ifelse(drug_col==0 & !is.na(lead(drug_col)) & lead(drug_col)==1, nextadd+1L, nextadd),
      nextadddrug=ifelse(drug_col==0 & !is.na(lead(drug_col)) & lead(drug_col)==1, ifelse(is.na(nextadddrug), i, paste(nextadddrug, "&", i)), nextadddrug)) %>%
  ungroup()
}

combo_substance_start_stop <- combo_substance_start_stop %>% analysis$cached("combo_substance_start_stop_interim_4", indexes=c("patid", "dcstartdate"))


combo_substance_start_stop <- combo_substance_start_stop %>%
 
 mutate(swap=add>=1 & rem>=1,
     nextswap=nextadd>=1 & nextrem>=1,
     
     drugchange=case_when(
      add>=1 & rem==0 ~ "add",
      add==0 & rem>=1 ~ "remove",
      add>=1 & rem>=1 ~ "swap",
      add==0 & rem==0 & drugcomboorder==1 ~ "start of px",
      add==0 & rem==0 & drugcomboorder!=1 ~ "stop - break"),
     
     nextdrugchange=case_when(
      nextadd>=1 & nextrem==0 ~ "add",
      nextadd==0 & nextrem>=1 ~ "remove",
      nextadd>=1 & nextrem>=1 ~ "swap",
      nextadd==0 & nextrem==0 & nextdcdate!=dcstopdate ~ "stop - break",
      nextadd==0 & nextrem==0 & nextdcdate==dcstopdate ~ "stop - end of px")) %>%
 
 analysis$cached("combo_substance_start_stop_interim_5", indexes=c("patid", "dcstartdate"))



# Add time until next drug combination (if last combination or before break, use stop date of current combination), time until a different drug substance added or removed, and time since previous combination prescribed, as well as date of next drug combo

combo_substance_start_stop <- combo_substance_start_stop %>%
 group_by(patid) %>%
 dbplyr::window_order(dcstartdate) %>%
 mutate(datechange_substance=ifelse(is.na(lead(dcstartdate)) | datediff(lead(dcstartdate), dcstopdate)>183, dcstopdate, lead(dcstartdate)),
     dateaddrem_substance=ifelse(is.na(lead(dcstartdate)), NA, lead(dcstartdate)),
     dateprevcombo_substance=lag(dcstartdate)) %>%
 ungroup()


# Add variable to indicate whether multiple drug substances started on the same day, plus timetochange, timetoaddrem and timeprevcombo variables

combo_substance_start_stop <- combo_substance_start_stop %>%
 mutate(multi_drug_start_substance=ifelse(add>1 | (drugcomboorder==1 & numdrugs_substance>1), 1L, 0L),
        timetochange_substance=datediff(datechange_substance, dcstartdate),
        timetoaddrem_substance=datediff(dateaddrem_substance, dcstartdate),
        timeprevcombo_substance=datediff(dcstartdate, dateprevcombo_substance)) %>% 
 analysis$cached("combo_substance_start_stop", indexes=c("patid", "dcstartdate"))

#combo_substance_start_stop %>% count()
#7,523,780


############################################################################################

# Combine combo_start_stop tables
## Only include variables which we are currently using and binary drug class / drug substance variables (Acarbose columns from two tables are identical: remove from drug class table)
## Add ncurrtx variable: number of distinct major drug CLASSES (DPP4, GIPGLP1, GLP1, INS, MFN, SGLT2, SU, TZD - i.e. not Acarbose or Glinides), not including one being initiated (i.e. DPP4+GIPGLP1+GLP1+INS+MFN+SGLT2+SU+TZD)
## If rows are only present when considering drug substance changes, ncurrtx is missing (NA)

## Copy down and recalculate timetochange_class, timetoaddrem_class and timeprevcombo_class for all rows

combo_start_stop <- combo_substance_start_stop %>%
  select(patid, dcstartdate, dcstopdate_substance=dcstopdate, drug_substance_combo, datechange_substance, dateaddrem_substance, dateprevcombo_substance, multi_drug_start_substance, all_of(drugsubstances), timetochange_substance, timetoaddrem_substance, timeprevcombo_substance) %>%
  left_join((combo_class_start_stop %>% select(patid, dcstartdate, dcstopdate_class=dcstopdate, drug_class_combo, datechange_class, dateaddrem_class, dateprevcombo_class, multi_drug_start_class, all_of(drugclasses), -Acarbose, timetochange_class, timetoaddrem_class, timeprevcombo_class)), by=c("patid", "dcstartdate")) %>%
  mutate(drug_class_combo_change=ifelse(!is.na(dcstopdate_class), 1L, 0L)) %>%
  
  group_by(patid) %>%
  dbplyr::window_order(dcstartdate) %>%
  mutate(drug_class_changes=cumsum(drug_class_combo_change==1)) %>%
  dbplyr::window_order() %>%
  ungroup() %>%
  analysis$cached("combo_start_stop_interim_1", indexes=c("patid", "drug_class_changes"))
 
 
combo_start_stop <- combo_start_stop %>%
  group_by(patid, drug_class_changes) %>%
  mutate(datechange_class=max(datechange_class, na.rm=TRUE),
         dateaddrem_class=max(dateaddrem_class, na.rm=TRUE),
         dateprevcombo_class=max(dateprevcombo_class, na.rm=TRUE),
         
         Acarbose=max(Acarbose, na.rm=TRUE),
         DPP4=max(DPP4, na.rm=TRUE),
         GIPGLP1=max(GIPGLP1, na.rm=TRUE),
         Glinide=max(Glinide, na.rm=TRUE),
         GLP1=max(GLP1, na.rm=TRUE),
         INS=max(INS, na.rm=TRUE),
         MFN=max(MFN, na.rm=TRUE),
         SGLT2=max(SGLT2, na.rm=TRUE),
         SU=max(SU, na.rm=TRUE),
         TZD=max(TZD, na.rm=TRUE)) %>%
  
  ungroup() %>%

  mutate(timetochange_class=datediff(datechange_class, dcstartdate),
         timetoaddrem_class=datediff(dateaddrem_class, dcstartdate),
         timeprevcombo_class=datediff(dcstartdate, dateprevcombo_class)) %>%
 
 select(patid, dcstartdate, dcstopdate_class, drug_class_combo, timetochange_class, timetoaddrem_class, timeprevcombo_class, multi_drug_start_class, all_of(drugclasses), dcstopdate_substance, drug_substance_combo, timetochange_substance, timetoaddrem_substance, timeprevcombo_substance, multi_drug_start_substance, all_of(drugsubstances)) %>%
 mutate(ncurrtx=DPP4+GIPGLP1+GLP1+INS+MFN+SGLT2+SU+TZD-1) %>%
 analysis$cached("combo_start_stop", indexes=c("patid", "dcstartdate"))

#combo_start_stop %>% count()
#7,523,780
