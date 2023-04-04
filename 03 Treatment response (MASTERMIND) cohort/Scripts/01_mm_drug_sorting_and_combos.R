
# Processes prescriptions to find start and stop dates for drugs, and when other drug classes added or remove relative to start date for drug class of interest

############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("mm")


############################################################################################

# Define drug classes

drugclasses <- c("Acarbose", "DPP4", "Glinide", "GLP1", "MFN", "SGLT2", "SU", "TZD", "INS")


############################################################################################

# Join and cache OHA and insulin prescriptions

analysis = cprd$analysis("all_patid")

clean_oha_prodcodes <- clean_oha_prodcodes %>% analysis$cached("clean_oha_prodcodes")
#clean_oha_prodcodes %>% count()
# 106,359,163


clean_insulin_prodcodes <- clean_insulin_prodcodes %>% analysis$cached("clean_insulin_prodcodes")
#clean_insulin_prodcodes %>% count()
# 23,537,104


insulin <- clean_insulin_prodcodes %>%
  mutate(Acarbose=0,
         DPP4=0,
         Glinide=0,
         GLP1=0,
         MFN=0,
         SGLT2=0,
         SU=0,
         TZD=0,
         INS=1,
         drug_substance1=insulin_cat,
         drug_substance2=NA) %>%
  select(-insulin_cat)

ohaandins <- clean_oha_prodcodes %>%
  union_all(insulin)

analysis = cprd$analysis("mm")

ohaandins <- ohaandins %>% analysis$cached("ohaandins", indexes=c("patid", "date"))

#ohaandins %>% count()
# 129,896,267


############################################################################################

# Sort out combination medications

## Raw data has single line for combination meds - expand so there is 1 line per drug class
## Raw data has drug_substance1 and drug_substance2 columns from ohaLookup on Slade
## Pivotting reshapes to give 1 line per drug substance
## First remove drugclasses columns (binary variables for each of the 9 classes) as won't be accurate after reshape
## Then join with drug_substance_class_lookup table to get drug classes (string variable) based on drug substance

## Check that no rows have NA in drug class columns - if so, will lose them at this stage


#ohaandins %>% filter(if_any(all_of(drugclasses), is.na)) %>% count()
# 0 - perfect

ohains <- ohaandins %>%
  select(-c(all_of(drugclasses))) %>%
  pivot_longer(cols=starts_with("drug_substance"), names_to="whichdrugsubstance", values_to="drugsubstance") %>%
  filter(!is.na(drugsubstance)) %>%
  select(-whichdrugsubstance) %>%
  left_join(cprd$tables$drugSubstanceClassLookup, by="drugsubstance")


############################################################################################

# Remove patid/date/drug class duplicates and make new summary coverage and drug substances variables

# Replace quantity, daily dose and duration with mean grouped by patid/date/drug class (first have to join with dosageid lookup to get daily_dose)

ohains <- ohains %>%
  left_join(cprd$tables$commonDose, by="dosageid") %>%
  group_by(patid, date, drugclass) %>%
  mutate(quantity = mean(quantity[quantity>0], na.rm=TRUE),
         daily_dose = mean(daily_dose[daily_dose>0], na.rm=TRUE),
         duration = mean(duration[duration>0], na.rm=TRUE)) %>%
  ungroup()


# Make new drug substances variable = list of all different drug substances (remove duplicates first) within patid/date/drug class
## Start by just removing patid / date / drug class / drug substance duplicates
  
ohains <- ohains %>% 
  group_by(patid, date, drugclass, drugsubstance) %>%
  filter(row_number()==1) %>%
  ungroup() %>%

  group_by(patid, date, drugclass, quantity, daily_dose, duration) %>%
  summarise(drugsubstances=sql("group_concat(distinct drugsubstance order by drugsubstance separator ' & ')")) %>%
  ungroup()
  

# Add coverage = quantity/daily dose where both available, otherwise = duration

ohains <- ohains %>%
  mutate(coverage = ifelse(!is.na(quantity) & !is.na(daily_dose), quantity/daily_dose, duration))


# Cache

ohains <- ohains %>% analysis$cached("ohains", indexes=c("patid", "date", "drugclass"))
  
  
############################################################################################

# all_scripts = 1 line per patid / date where script issued, with drug class info in wide format

# Define whether date is start or stop for each drug class
## Find time from previous script (dprevuse) and to next script (dnextuse) for same person and same drug class
## If no previous script/previous script more than 6 months (183 days) earlier, define as start date (dstart=1)
## If no next script/next script more than 6 months (183 days) later, define as stop date (dstop=1)

all_scripts_long <- ohains %>%
  group_by(patid, drugclass) %>%
  dbplyr::window_order(date) %>%
  mutate(dnextuse=datediff(lead(date), date),
         dprevuse=datediff(date, lag(date)),
         dstart=dprevuse>183 | is.na(dprevuse),
         dstop=dnextuse>183 | is.na(dnextuse)) %>%
  ungroup()


# Define number of drug classes prescribed (numpxdate), started (numstart) and stopped on each date (numstop)

all_scripts_long <- all_scripts_long %>%
  group_by(patid, date) %>%
  mutate(numpxdate=n(),
         numstart=sum(dstart, na.rm=TRUE),
         numstop=sum(dstop, na.rm=TRUE)) %>%
  ungroup()

all_scripts_long <- all_scripts_long %>% analysis$cached("all_scripts_long", indexes=c("patid", "date", "drugclass"))


# Reshape wide by drug class - so 1 row per patid/date

all_scripts <- all_scripts_long %>%
  pivot_wider(c(patid, date, numpxdate, numstart, numstop),
              names_from=drugclass,
              values_from=c(dstart, dstop, coverage, drugsubstances),
              values_fill=list(dstart=FALSE, dstop=FALSE)) %>%
  analysis$cached("all_scripts_interim_1", indexes=c("patid", "date"))


# Use numstart and numstop to work out total number of drug classes patient is on at each date (numdrugs; they can be on a drug even if not prescribed on that date)
## Add numstop to numdrugs so that drug stopped is included in numdrugs count on the date it is stopped
  
all_scripts <- all_scripts %>%
  group_by(patid) %>%
  dbplyr::window_order(date) %>%
  mutate(cu_numstart=cumsum(numstart),
         cu_numstop=cumsum(numstop),
         numdrugs=cu_numstart-cu_numstop+numstop) %>%
  ungroup()


# Make variable for what combination of drugs patient is on at each date
## First make binary variables for each drug for whether patient was on the drug (whether or not prescribed) at each date
## When this was initially run, it took a very long time (5-6 hours) as each iteration of the loop produces another temporary table - so have removed loop here and 2 loops in subsequent code

all_scripts <- all_scripts %>%
  group_by(patid) %>%
  dbplyr::window_order(date) %>%
  mutate(Acarbose=cumsum(dstart_Acarbose)>cumsum(dstop_Acarbose) | dstart_Acarbose==1 | dstop_Acarbose==1,
         DPP4=cumsum(dstart_DPP4)>cumsum(dstop_DPP4) | dstart_DPP4==1 | dstop_DPP4==1,
         Glinide=cumsum(dstart_Glinide)>cumsum(dstop_Glinide) | dstart_Glinide==1 | dstop_Glinide==1,
         GLP1=cumsum(dstart_GLP1)>cumsum(dstop_GLP1) | dstart_GLP1==1 | dstop_GLP1==1,
         MFN=cumsum(dstart_MFN)>cumsum(dstop_MFN) | dstart_MFN==1 | dstop_MFN==1,
         SGLT2=cumsum(dstart_SGLT2)>cumsum(dstop_SGLT2) | dstart_SGLT2==1 | dstop_SGLT2==1,
         SU=cumsum(dstart_SU)>cumsum(dstop_SU) | dstart_SU==1 | dstop_SU==1,
         TZD=cumsum(dstart_TZD)>cumsum(dstop_TZD) | dstart_TZD==1 | dstop_TZD==1,
         INS=cumsum(dstart_INS)>cumsum(dstop_INS) | dstart_INS==1 | dstop_INS==1) %>%
  ungroup() %>% 
  analysis$cached("all_scripts_interim_2", indexes=c("patid", "date"))


# Add in insulin start and stop dates

all_scripts <- all_scripts %>%
  group_by(patid) %>%
  dbplyr::window_order(date) %>%
  mutate(INS_startdate=if_else(dstart_INS==1, date, as.Date(NA)),
         INS_stopdate=if_else(dstop_INS==1, date, as.Date(NA))) %>%
  fill(INS_startdate, .direction="down") %>%
  fill(INS_stopdate, .direction="up") %>%
  mutate(INS_startdate=if_else(INS==0, as.Date(NA), INS_startdate),
         INS_stopdate=if_else(INS==0, as.Date(NA), INS_stopdate)) %>%
  ungroup() %>% 
  analysis$cached("all_scripts_interim_3", indexes=c("patid", "date"))


## Use binary drug class columns to make single 'drugcombo' column with the names of all the drug classes patient is on at each date
## Previous step ran really slowly (5-6 hours) - each iteration of the loop produces another temporary table - so have removed 2 x loops here

all_scripts <- all_scripts %>%
  select(-c(starts_with("dstart"), starts_with("dstop"))) %>%
  mutate(drugcombo=paste0(ifelse(Acarbose==1, "Acarbose_", NA),
                          ifelse(DPP4==1, "DPP4_", NA),
                          ifelse(Glinide==1, "Glinide_", NA),
                          ifelse(GLP1==1, "GLP1_", NA),
                          ifelse(MFN==1, "MFN_", NA),
                          ifelse(SGLT2==1, "SGLT2_", NA),
                          ifelse(SU==1, "SU_", NA),
                          ifelse(TZD==1, "TZD_", NA),
                          ifelse(INS==1, "INS_", NA)),
         
         drugcombo=ifelse(str_sub(drugcombo, -1, -1)=="_", str_sub(drugcombo, 1, -2), drugcombo))


# Recalculate numdrugs (number of different drug classes patient is on at each date) and check it matches earlier calculation

all_scripts <- all_scripts %>%
  mutate(numdrugs2=Acarbose + DPP4 + Glinide + GLP1 + MFN + SGLT2 + SU + TZD + INS)

all_scripts <- all_scripts %>% analysis$cached("all_scripts_interim_4", indexes=c("patid", "date", "drugcombo"))

#all_scripts %>% filter(numdrugs!=numdrugs2 | (is.na(numdrugs) & !is.na(numdrugs2)) | (!is.na(numdrugs) & is.na(numdrugs2))) %>% count()
# 0 - perfect


# Define whether date is start or stop for each drug combination
## Coded differently to drug classes as patient can only be on one combination at once 
## Find time from previous script (dcprevuse) and to next script (dncextuse) for same person and same drug combo
## If previous script is for a different drug combo or no previous script, define as start date (dcstart=1)
## If next script is for a different drug combo or no next script, define as stop date (dcstop=1)

all_scripts <- all_scripts %>%
  group_by(patid, drugcombo) %>%
  dbplyr::window_order(date) %>%
  mutate(dcnextuse=datediff(lead(date), date),
         dcprevuse=datediff(date, lag(date))) %>%
  ungroup() %>%
  
  group_by(patid) %>%
  dbplyr::window_order(date) %>%
  mutate(dcstart=drugcombo!=lag(drugcombo) | is.na(dcprevuse),
         dcstop=drugcombo!=lead(drugcombo) | is.na(dcnextuse)) %>%
  ungroup()


# Add 'gaps': defined as break of >6 months (183 days) in prescribing of combination
## Update start and stop dates based on these

all_scripts <- all_scripts %>%
  group_by(patid) %>%
  dbplyr::window_order(date) %>%
  mutate(stopgap=ifelse(dcnextuse>183 & drugcombo==lead(drugcombo), 1L, NA),
         startgap=ifelse((dcprevuse>183 | is.na(dcprevuse)), 1L, NA),
         dcstop=ifelse(!is.na(stopgap) & stopgap==1 & dcstop==0, 1L, dcstop),
         dcstart=ifelse(!is.na(startgap) & startgap==1 & dcstart==0, 1L, dcstart)) %>%
  ungroup()


# Add in time to last prescription date for each patient (any drug class)

all_scripts <- all_scripts %>%
  group_by(patid) %>%
  mutate(timetolastpx=datediff(max(date, na.rm=TRUE), date)) %>%
  ungroup()
  

# Cache

all_scripts <- all_scripts %>% analysis$cached("all_scripts", indexes=c("patid", "date", "drugcombo"))


############################################################################################

# drug_start_stop = 1 line per patid / drug class instance (continuous period of drug use)

# Just keep dates where a drug is started or stopped
## Pull out start and stop dates on rows where dstart==1
## Each row either has both start and stop date, or start on one date and next date for same patid and drug class will be stop date

drug_start_stop <- all_scripts_long %>%
  filter(dstart==1 | dstop==1) %>%
  
  group_by(patid, drugclass) %>%
  dbplyr::window_order(date) %>%
  mutate(dstartdate=if_else(dstart==1, date, as.Date(NA)),
         dstopdate=if_else(dstart==1 & dstop==1, date, 
                           if_else(dstart==1 & dstop==0, lead(date), as.Date(NA))),
         int_stopdatepluscov=sql("date_add(date, interval coverage day)"),
         dstopdatepluscov=if_else(dstart==1 & dstop==1, int_stopdatepluscov,
                                  if_else(dstart==1 & dstop==0, lead(int_stopdatepluscov), as.Date(NA)))) %>%
  ungroup()


# Just keep rows where dstart==1 - 1 row per drug instance, and only keep variables which apply to whole instance, not those relating to specific scripts within the instance

drug_start_stop <- drug_start_stop %>%
  filter(dstart==1) %>%
  select(patid, drugclass, dstartdate, dstopdate, dstopdatepluscov, drugsubstances)


# Define time on drug

drug_start_stop <- drug_start_stop %>%
  mutate(timeondrug=datediff(dstopdate, dstartdate),
         timeondrugpluscov=datediff(dstopdatepluscov, dstartdate))


# Add drug order count within each patid: how many periods of medication have they had
## If multiple meds started on same day, use minimum for both/all drugs

drug_start_stop <- drug_start_stop %>%
  group_by(patid) %>%
  dbplyr::window_order(dstartdate) %>%
  mutate(drugorder=row_number()) %>%
  ungroup() %>%
  
  group_by(patid, dstartdate) %>%
  mutate(drugorder=min(drugorder, na.rm=TRUE)) %>%
  ungroup()
           

# Add drug instance count for each patid / drug class instance e.g. if several periods of MFN usage, these should be labelled 1, 2 etc. based on start date

drug_start_stop <- drug_start_stop %>%
  group_by(patid, drugclass) %>%
  dbplyr::window_order(dstartdate) %>%
  mutate(druginstance=row_number()) %>%
  ungroup()


# Add drug line for each patid / drug class: on first usage of this drug, how many previous distinct drug classes had been used + 1 
## If multiple meds started on same day, use minimum for both/all drugs

drug_line <- drug_start_stop %>%
  filter(druginstance==1) %>%   # same as just keeping 1 row per patid/ drug class with minimum start date
  group_by(patid) %>%
  dbplyr::window_order(dstartdate) %>%
  mutate(drugline_all=row_number()) %>%
  ungroup() %>%
  
  group_by(patid, dstartdate) %>%
  mutate(drugline_all=min(drugline_all, na.rm=TRUE)) %>%
  ungroup() %>%
  
  select(patid, drugclass, drugline_all) 

drug_start_stop <- drug_start_stop %>%
  inner_join(drug_line, by=c("patid", "drugclass"))


# Cache

drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop", indexes=c("patid", "dstartdate", "drugclass", "druginstance"))


############################################################################################

# combo_start_stop = 1 line per patid / drug combo instance (continuous period of drug combo use)

# Similar process to that for drug classes above:
## Just keep dates where a drug is started or stopped
## Pull out start and stop dates on rows where dcstart==1
## Each row either has both start and stop date, or start on one date and next date for same patid will be stop date (as can only be on one drug combo at once)

combo_start_stop <- all_scripts %>%
  filter(dcstart==1 | dcstop==1) %>%
  
  group_by(patid) %>%
  dbplyr::window_order(date) %>%
  mutate(dcstartdate=if_else(dcstart==1, date, as.Date(NA)),
         dcstopdate=if_else(dcstart==1 & dcstop==1, date, 
                           if_else(dcstart==1 & dcstop==0, lead(date), as.Date(NA)))) %>%
  ungroup()


# Just keep rows where dcstart==1 - 1 row per drug combo instance, and only keep variables which apply to whole instance

combo_start_stop <- combo_start_stop %>%
  filter(dcstart==1) %>%
  select(patid, all_of(drugclasses), drugcombo, numdrugs, dcstartdate, dcstopdate, INS_startdate, INS_stopdate)


# Add drugcomborder count within each patid: how many periods of medication have they had
## Also add 'nextdcdate': date next combination started (use stop date if last combination before end of prescriptions)

combo_start_stop <- combo_start_stop %>%
  group_by(patid) %>%
  dbplyr::window_order(dcstartdate) %>%
  mutate(drugcomboorder=row_number(),
         nextdcdate=if_else(is.na(lead(dcstartdate)), dcstopdate, lead(dcstartdate))) %>%
  ungroup()


# Define what current and next drug combination represents in terms of adding/removing/swapping

combo_start_stop <- combo_start_stop %>%
  mutate(add=0L,
         adddrug=NA,
         rem=0L,
         remdrug=NA,
         nextadd=0L,
         nextadddrug=NA,
         nextrem=0L,
         nextremdrug=NA,
         )

for (i in drugclasses) {
  
  drug_col <- as.symbol(i)
  
  combo_start_stop <- combo_start_stop %>%
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

combo_start_stop <- combo_start_stop %>% analysis$cached("combo_start_stop_interim_1", indexes=c("patid", "dcstartdate"))


combo_start_stop <- combo_start_stop %>%
  
  mutate(swap=add>=1 & rem>=1,
         nextswap=nextadd>=1 & nextrem>=1,
         
         drugchange=case_when(
    add>=1 & rem==0 ~ "add",
    add==0 & rem>=1 ~ "remove",
    add>=1 & rem>=1 ~ "swap",
    add==0 & rem==0 & drugcomboorder==1 ~ "start of px",
    add==0 & rem==0 & drugcomboorder!=1  ~ "stop - break"),
    
    nextdrugchange=case_when(
      nextadd>=1 & nextrem==0 ~ "add",
      nextadd==0 & nextrem>=1 ~ "remove",
      nextadd>=1 & nextrem>=1 ~ "swap",
      nextadd==0 & nextrem==0 & nextdcdate!=dcstopdate ~ "stop - break",
      nextadd==0 & nextrem==0 & nextdcdate==dcstopdate ~ "stop - end of px"))



# Add time until next drug combination (if last combination or before break, use stop date of current combination), time until a different drug class added or removed, and time since previous combination prescribed, as well as date of next drug combo

combo_start_stop <- combo_start_stop %>%
  group_by(patid) %>%
  dbplyr::window_order(dcstartdate) %>%
  mutate(timetochange=ifelse(is.na(lead(dcstartdate)) | datediff(lead(dcstartdate),dcstopdate)>183, datediff(dcstopdate, dcstartdate), datediff(lead(dcstartdate), dcstartdate)),
         timetoaddrem=ifelse(is.na(lead(dcstartdate)), NA, datediff(lead(dcstartdate), dcstartdate)),
         timeprevcombo=datediff(dcstartdate, lag(dcstartdate))) %>%
  ungroup()


# Add variable to indicate whether multiple drug classes started on the same day
## Updated 28/03/2023 as realised this is missing if no prior drug periods

combo_start_stop <- combo_start_stop %>%
  mutate(multi_drug_start=ifelse(add>1 | (drugcomboorder==1 & numdrugs>1), 1L, 0L))


# Cache

combo_start_stop <- combo_start_stop %>% analysis$cached("combo_start_stop", indexes=c("patid", "dcstartdate"))

