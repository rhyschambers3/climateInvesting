
# 1. Libraries ------------------------------------------------------------

# This allows for easy manipulation of the data
library(tidyverse)

options(scipen = 100)
# 2. Functions ------------------------------------------------------------

# All the important functions are here
source("R/key_functions.R")

### Improvement in predictions

# Read in the Fama-French and BMG factors
# 3. Data -----------------------------------------------------------------

# * 3.1 - Carbon Risk Factor ----------------------------------------------
# carbon_data <- read_csv("data/bmg_carima.csv")   
#carbon_data <- read_csv("data/bmg_eu_ets.csv")
#carbon_data <- read_csv("data/bmg_acwi_crbn.csv")
# carbon_data <- read_csv("data/bmg_xop_smog.csv")
#carbon_data <- read_csv("data/bmg_xop_smog_orthogonalized_1.csv")   # XOP-SMOG orthogonalized for Rate Change, Curve Change, BBB Spread Change
#carbon_data <- read_csv("data/bmg_xop_smog_orthogonalized_2.csv")  # XOP-SMOG additionally orthogonalized for HML Fama-French factor
#carbon_data <- read_csv("data/bmg_wmat_crbn_mat.csv")
# carbon_data <- read_csv("data/bmg_carima_orthogonalized.csv")
carbon_data <- read_csv("data/bmg_xop_smog_wmat_crbn_mat.csv")

# carbon_data <- read_csv("data/paris_aligned_bmg.csv") %>%
#  select(-Green_Returns, - Brown_Returns)

# * 3.2  - Fama-French Factors --------------------------------------------

ff_data <- read_csv("data/ff_factors.csv")

# * 3.3 - Risk Free -------------------------------------------------------

risk_free <- read_csv("data/risk_free.csv")

# Read in the SPX return data from the bulk downloader
final_stock_returns <- read.csv('data/msci_constituent_returns.csv') # for msci
#final_stock_returns <- read.csv('data/msci_world_returns.csv') # for msci
#final_stock_returns <- read.csv('data/spx_constituent_returns.csv') # for spx
#final_stock_returns <- read.csv('data/msci_sector_returns.csv') # for msci

# Debug - write.csv(final_stock_returns[final_stock_returns$Stock=="ORA.PA",], "final_stock_returns.csv")

# 4. Data Preprocessing -----------------------------------------------------

final_stock_returns[, 1] <- as.Date(final_stock_returns[, 1])
final_stock_returns <- as_tibble(final_stock_returns)

# Making the date column have the same name  for the join later
colnames(carbon_data)[1] <- "Date"
colnames(ff_data)[1] <- "Date"
colnames(risk_free)[1] <- "Date"

# Turning the Fama-French factors from number percentage to decimals
ff_data[, -1] <- ff_data[, -1]/100
risk_free[, -1] <- risk_free[, -1]/100

# Combine the carbon data with the Fama-French factors
all_factor_data <- carbon_data %>%
  left_join(
    ff_data,
    by = c("Date" = "Date")
    ) %>%
  left_join(
    risk_free,
    by = c("Date"="Date")
    )

all_data <- final_stock_returns %>%
  inner_join(
    all_factor_data,
    by = c("Date" = "Date")
    ) %>%
  mutate(excess_returns = Returns - Rf) %>%
  rename(Mkt_less_RF = `Mkt-RF`) # Change market return data column to be more compatible

# 5. Regression Analysis --------------------------------------------------

# Create a blank dataframe
pred_power <- c()

stock_names <- unique(all_data$Stock)

# * 5.1 - Get the regression of all stocks -------------------------------
### Run all necessary regression ###

mass_reg_results <- mass_regression(
  stock_data     = all_data,
  stock_col_name = "Stock",
  reg_formulas   = c(
    "excess_returns ~ Mkt_less_RF + SMB + HML + WML",
    "excess_returns ~ BMG + Mkt_less_RF + SMB + HML + WML")
  )

get_no_bmg_regression_results <- lapply(mass_reg_results, function(x) {
  summary(x[["Regression"]][[1]])
})

get_bmg_regression_results <- lapply(mass_reg_results, function(x) {
  summary(x[["Regression"]][[2]])
})

# * 5.2 - Get the coefficient summary table, R-Squared and Adjuste --------

bmg_pred_data <- lapply(get_bmg_regression_results, function(x) {
  if (get_dataframe_dimensions(x$coefficients)[1] > 2)
  {
    data.frame(t(x$coefficients[, 1]),
               x$r.squared,
               x$adj.r.squared)
  }
})

no_bmg_pred_data <- lapply(get_no_bmg_regression_results, function(x) {
  if (get_dataframe_dimensions(x$coefficients)[1] > 2)
  {
    data.frame(t(x$coefficients[, 1]),
               x$r.squared,
               x$adj.r.squared)
  }
})

bmg_pred_data_t <- lapply(get_bmg_regression_results, function(x) {
  if (get_dataframe_dimensions(x$coefficients)[1] > 2)
  {
    data.frame(t(x$coefficients[, 3]))
  }
})

no_bmg_pred_data_t <- lapply(get_no_bmg_regression_results, function(x) {
  if (get_dataframe_dimensions(x$coefficients)[1] > 2)
  {
    data.frame(t(x$coefficients[, 3]))
  }
})

# * 5.3 - Removing regressions that didn't run ----------------------------

if (length(which(lapply(bmg_pred_data, function(x) is.null(x)) == TRUE)) > 0) {
  bmg_pred_data <- bmg_pred_data[-which(lapply(bmg_pred_data, function(x) is.null(x)) == TRUE)]
  bmg_pred_data_t <- bmg_pred_data_t[-which(lapply(bmg_pred_data_t, function(x) is.null(x)) == TRUE)]
}

if (length(which(lapply(no_bmg_pred_data, function(x) is.null(x)) == TRUE)) > 0) {
  no_bmg_pred_data <- no_bmg_pred_data[-which(lapply(no_bmg_pred_data, function(x) is.null(x)) == TRUE)]
  no_bmg_pred_data_t <- no_bmg_pred_data_t[-which(lapply(no_bmg_pred_data_t, function(x) is.null(x)) == TRUE)]
}

# * 5.4 - Final Output Table ----------------------------------------------

bmg_pred_data <- tibble(
  Stock = names(bmg_pred_data),
  bind_rows(bmg_pred_data)
  )

no_bmg_pred_data <- tibble(
  Stock = names(no_bmg_pred_data),
  bind_rows(no_bmg_pred_data)
  )

bmg_pred_data_t <- tibble(
  Stock = names(bmg_pred_data_t),
  bind_rows(bmg_pred_data_t)
  )

no_bmg_pred_data_t <- tibble(
  Stock = names(no_bmg_pred_data_t),
  bind_rows(no_bmg_pred_data_t)
  )

colnames(bmg_pred_data)[2:9] <- c("FFB_Alpha", "FFB_BMG", "FFB_Mkt_less_RF", "FFB_SMB", "FFB_HML", "FFB_WML", "FFB_Rsq", "FFB_AdjRsq")
colnames(no_bmg_pred_data)[2:8] <- c("FF_Alpha",  "FF_Mkt_less_RF", "FF_SMB", "FF_HML", "FF_WML","FF_Rsq", "FF_AdjRsq")



# 6. T-Statistic & Coefficient Row Binding --------------------------------

full_bmg_table <- c()

for (i in 1:nrow(bmg_pred_data)) {
  temp_t_holder <- cbind(bmg_pred_data_t[i ,], 0, 0)
  colnames(temp_t_holder) <- colnames(bmg_pred_data)

  temp_holder <- bind_rows(
    bmg_pred_data[i, ],
    temp_t_holder
    ) %>%
    mutate(
      Statistic = c("Coefficient", "t-Stat")
      ) %>%
    relocate(Statistic, .after = Stock)

  full_bmg_table <- bind_rows(
    full_bmg_table,
    temp_holder
    )

}

full_no_bmg_table <- c()

for (i in 1:nrow(bmg_pred_data)) {
  temp_t_holder <- cbind(no_bmg_pred_data_t[i ,], 0, 0)
  colnames(temp_t_holder) <- colnames(no_bmg_pred_data)

  temp_holder <- bind_rows(
    no_bmg_pred_data[i, ],
    temp_t_holder
    ) %>%
    mutate(
      Statistic = c("Coefficient", "t-Stat")
    ) %>%
    relocate(Statistic, .after = Stock)

  full_no_bmg_table <- bind_rows(
    full_no_bmg_table,
    temp_holder
    )
}

# * 6.1 - Display the full table ------------------------------------------

full_bmg_table
full_no_bmg_table

# * 6.2 - Write the table -------------------------------------------------

write.csv(full_bmg_table, "full_bmg_table.csv")
write.csv(full_no_bmg_table, "full_no_bmg_table.csv")

pred_power <- bmg_pred_data %>%
  inner_join(
    no_bmg_pred_data,
    by = c("Stock" = "Stock")
    )

pred_power <- pred_power %>%
  relocate(FF_Rsq, .after = Stock) %>%
  relocate(FFB_Rsq, .after = FF_Rsq) %>%
  relocate(FF_AdjRsq, .after = FFB_Rsq) %>%
  relocate(FFB_AdjRsq, .after = FF_AdjRsq) %>%
  relocate(FF_Alpha, .after = FFB_Alpha)

# 7 - By Sector Analysis --------------------------------------------------

# * 7.1 Sector Data -------------------------------------------------------

# Read in the sector breakdowns
final_stock_breakdown <- read_csv("data/msci_constituent_details.csv") # for msci
# final_stock_breakdown <- read_csv("data/spx_sector_breakdown.csv") # for spx

pred_power <- pred_power %>%
  inner_join(
    final_stock_breakdown,
 # by = c("Stock" = "Symbol")
 # )   for spx
  by = c("Stock" = "Ticker")
  )   # for msci

### This is for SPX Only
colnames(pred_power)[(length(colnames(pred_power)) - 1):length(colnames(pred_power))] <- c("Sector", "Sub_Sector")

# * 7.2 - Mean Predictive Power by Sector Summarisation -------------------

### Working on financials ###
unique(pred_power$Sub_Sector)
pred_power <- pred_power %>%
  mutate(final_sector = Sector)

financial_sectors <- c("Multi-Sector Holdings",
                       "Diversified Banks",
                       "Investment Banking & Brokerage",
                       "Asset Management & Custody Bank",
                       "Financial Exchanges & Data",
                       "Consumer Finance",
                       "Regional Banks",
                       "Property & Casualty Insurance",
                       "Insurance Brokers",
                       "Life & Health Insurance",
                       "Multi-line Insurance",
                       "Reinsurance",
                       "Thrifts & Mortgage Finance")

pred_power_table <- pred_power %>%
  mutate(
    Alpha_Diff  = abs(FFB_Alpha) - abs(FF_Alpha),
    RSq_Diff    = FFB_Rsq - FF_Rsq,
    AdjRSq_Diff = FFB_AdjRsq - FF_AdjRsq
    ) %>%
  ### Change the below line by what you want to group things by
  group_by(Sector) %>%
  summarise(
    across(where(is.double), mean)
  )

# * 7.3 - Mean Predictive Power by each Factor across all Stocks ----------

all_sector_pred_power <- pred_power %>%
  summarise(
    across(where(is.double), mean)
  )

# Display tables by sector and average of all stocks
pred_power_table
all_sector_pred_power

# Write table
write.csv(pred_power_table, "MSCI Predictive Power Table by Sector.csv")


# * 8.1 - Creating equally-weighted portfolios -----------------------------

# Read in the sector breakdowns
final_stock_breakdown <- read_csv("data/msci_constituent_details.csv") # for msci
# final_stock_breakdown <- read_csv("data/spx_sector_breakdown.csv") # for spx

all_data_sectors <- all_data %>%
  left_join(final_stock_breakdown, by = c("Stock" = "Ticker"))

all_data_sectors <- all_data_sectors %>%
  group_by(Sector, Date) %>%
  summarise(excess_returns = mean(excess_returns))

all_data_sectors <- all_data_sectors %>%
  left_join(
    all_factor_data,
    by = c("Date" = "Date")) %>%
  rename(Mkt_less_RF = `Mkt-RF`)

# * 8.2 - Regression Analysis by Sector -----------------------------------

mass_reg_results_by_sector <- mass_regression(
  stock_data     = all_data_sectors,
  stock_col_name = "Sector",
  reg_formulas   = c(
    "excess_returns ~ Mkt_less_RF + SMB + HML + WML",
    "excess_returns ~ BMG + Mkt_less_RF + SMB + HML + WML"),
  by_sector      = TRUE
)

get_no_bmg_regression_results_by_sector <- lapply(mass_reg_results_by_sector, function(x) {
  summary(x[["Regression"]][[1]])
})

get_bmg_regression_results_by_sector <- lapply(mass_reg_results_by_sector, function(x) {
  summary(x[["Regression"]][[2]])
})

# * 8.3 - Get the coefficient summary table, R-Squared and Adjuste --------

no_bmg_pred_data_by_sector <- lapply(get_no_bmg_regression_results_by_sector, function(x) {
  if (get_dataframe_dimensions(x$coefficients)[1] > 2)
  {
    data.frame(t(x$coefficients[, 1]),
               x$r.squared,
               x$adj.r.squared)
  }
})

bmg_pred_data_by_sector <- lapply(get_bmg_regression_results_by_sector, function(x) {
  if (get_dataframe_dimensions(x$coefficients)[1] > 2)
  {
    data.frame(t(x$coefficients[, 1]),
               x$r.squared,
               x$adj.r.squared)
  }
})

no_bmg_pred_data_t_by_sector <- lapply(get_no_bmg_regression_results_by_sector, function(x) {
  if (get_dataframe_dimensions(x$coefficients)[1] > 2)
  {
    data.frame(t(x$coefficients[, 3]))
  }
})

bmg_pred_data_t_by_sector <- lapply(get_bmg_regression_results_by_sector, function(x) {
  if (get_dataframe_dimensions(x$coefficients)[1] > 2)
  {
    data.frame(t(x$coefficients[, 3]))
  }
})

# * 8.4 - Removing regressions that didn't run ----------------------------

# BMG
if (length(which(lapply(bmg_pred_data_by_sector, function(x) is.null(x)) == TRUE)) > 0) {
  bmg_pred_data_by_sector <- bmg_pred_data_by_sector[-which(lapply(bmg_pred_data_by_sector, function(x) is.null(x)) == TRUE)]
  bmg_pred_data_t_by_sector <- bmg_pred_data_t_by_sector[-which(lapply(bmg_pred_data_t_by_sector, function(x) is.null(x)) == TRUE)]
}

# no BMG
if (length(which(lapply(no_bmg_pred_data_by_sector, function(x) is.null(x)) == TRUE)) > 0) {
  no_bmg_pred_data_by_sector <- no_bmg_pred_data_by_sector[-which(lapply(no_bmg_pred_data_by_sector, function(x) is.null(x)) == TRUE)]
  bmg_pred_data_t_by_sector <- bmg_pred_data_t_by_sector[-which(lapply(bmg_pred_data_t_by_sector, function(x) is.null(x)) == TRUE)]
}

# * 8.5 - Final Output Table ----------------------------------------------

bmg_pred_data_by_sector <- tibble(
  Sector = names(bmg_pred_data_by_sector),
  bind_rows(bmg_pred_data_by_sector)
)

no_bmg_pred_data_by_sector <- tibble(
  Sector = names(no_bmg_pred_data_by_sector),
  bind_rows(no_bmg_pred_data_by_sector)
)

bmg_pred_data_t_by_sector <- tibble(
  Sector = names(bmg_pred_data_t_by_sector),
  bind_rows(bmg_pred_data_t_by_sector)
)

no_bmg_pred_data_t_by_sector <- tibble(
  Sector = names(no_bmg_pred_data_t_by_sector),
  bind_rows(no_bmg_pred_data_t_by_sector)
)

colnames(bmg_pred_data_by_sector)[2:9] <- c("FFB_Alpha", "FFB_BMG", "FFB_Mkt_less_RF", "FFB_SMB", "FFB_HML", "FFB_WML", "FFB_Rsq", "FFB_AdjRsq")
colnames(no_bmg_pred_data_by_sector)[2:8] <- c("FF_Alpha",  "FF_Mkt_less_RF", "FF_SMB", "FF_HML", "FF_WML","FF_Rsq", "FF_AdjRsq")


# * 8.6 - T-Statistic & Coefficient Row Binding ---------------------------

full_bmg_table_by_sector <- c()

# BMG by Sector Stats
for (j in 1:nrow(bmg_pred_data_by_sector)) {

  temp_t_holder <- cbind(bmg_pred_data_t_by_sector[j ,], 0, 0)
  colnames(temp_t_holder) <- colnames(bmg_pred_data_by_sector)

  temp_holder <- bind_rows(
    bmg_pred_data_by_sector[j, ],
    temp_t_holder
    ) %>%
    mutate(
      Statistic = c("Coefficient", "t-Stat")
    ) %>%
    relocate(Statistic, .after = Sector)

  full_bmg_table_by_sector <- bind_rows(
    full_bmg_table_by_sector,
    temp_holder
  )

}

full_no_bmg_table_by_sector <- c()

# No BMG Stats by Sector
for (i in 1:nrow(bmg_pred_data_by_sector)) {
  temp_t_holder <- cbind(no_bmg_pred_data_t_by_sector[i ,], 0, 0)
  colnames(temp_t_holder) <- colnames(no_bmg_pred_data_by_sector)

  temp_holder <- bind_rows(
    no_bmg_pred_data_by_sector[i, ],
    temp_t_holder
    ) %>%
    mutate(
      Statistic = c("Coefficient", "t-Stat")
    ) %>%
    relocate(Statistic, .after = Sector)

  full_no_bmg_table_by_sector <- bind_rows(
    full_no_bmg_table_by_sector,
    temp_holder
    )
}


# * 8.7 - Display the full table ------------------------------------------

full_bmg_table_by_sector
full_no_bmg_table_by_sector

# * 8.8 - Write data ----------------------------------------------------------

write.csv(full_bmg_table_by_sector, "full_bmg_table.csv")
write.csv(full_no_bmg_table_by_sector, "full_no_bmg_table.csv")

pred_power_by_sector <- bmg_pred_data_by_sector %>%
  inner_join(
    no_bmg_pred_data_by_sector,
    by = c("Sector" = "Sector") # Check name of column
  )

pred_power_by_sector <- pred_power_by_sector %>%
  relocate(FF_Rsq, .after = Sector) %>%
  relocate(FFB_Rsq, .after = FF_Rsq) %>%
  relocate(FF_AdjRsq, .after = FFB_Rsq) %>%
  relocate(FFB_AdjRsq, .after = FF_AdjRsq) %>%
  relocate(FF_Alpha, .after = FFB_Alpha)


# * 9.1 - Using sector ETFs for breakdowns  --------------------------------

# Read in the Sector ETFs  -------------------------------------------------

final_sector_returns <- read_csv("data/msci_sector_returns.csv") # for msci
# final_stock_breakdown <- read_csv("data/spx_sector_breakdown.csv") # for spx
sector_etf_mapping <- read_csv("data/msci_etf_sector_mapping.csv")
final_sector_returns <- final_sector_returns %>%
  left_join(sector_etf_mapping, by = c("Stock" = "ETF")) %>%
  filter(Stock != "XWD.TO")

all_data_sectors <- final_sector_returns %>%
  inner_join(
    all_factor_data,
    by = c("Date" = "Date")
  ) %>%
  mutate(excess_returns = Returns - Rf) %>%
  rename(Mkt_less_RF = `Mkt-RF`) # Change market return data column to be more compatible


# * 9.2 - Regression Analysis by Sector -----------------------------------

mass_reg_results_by_sector <- mass_regression(
  stock_data     = all_data_sectors,
  stock_col_name = "Sector",
  reg_formulas   = c(
    "excess_returns ~ Mkt_less_RF + SMB + HML + WML",
    "excess_returns ~ BMG + Mkt_less_RF + SMB + HML + WML"),
  by_sector      = TRUE
)

get_no_bmg_regression_results_by_sector <- lapply(mass_reg_results_by_sector, function(x) {
  summary(x[["Regression"]][[1]])
})

get_bmg_regression_results_by_sector <- lapply(mass_reg_results_by_sector, function(x) {
  summary(x[["Regression"]][[2]])
})

# * 9.3 - Get the coefficient summary table, R-Squared and Adjuste --------

no_bmg_pred_data_by_sector <- lapply(get_no_bmg_regression_results_by_sector, function(x) {
  if (get_dataframe_dimensions(x$coefficients)[1] > 2)
  {
    data.frame(t(x$coefficients[, 1]),
               x$r.squared,
               x$adj.r.squared)
  }
})

bmg_pred_data_by_sector <- lapply(get_bmg_regression_results_by_sector, function(x) {
  if (get_dataframe_dimensions(x$coefficients)[1] > 2)
  {
    data.frame(t(x$coefficients[, 1]),
               x$r.squared,
               x$adj.r.squared)
  }
})

no_bmg_pred_data_t_by_sector <- lapply(get_no_bmg_regression_results_by_sector, function(x) {
  if (get_dataframe_dimensions(x$coefficients)[1] > 2)
  {
    data.frame(t(x$coefficients[, 3]))
  }
})

bmg_pred_data_t_by_sector <- lapply(get_bmg_regression_results_by_sector, function(x) {
  if (get_dataframe_dimensions(x$coefficients)[1] > 2)
  {
    data.frame(t(x$coefficients[, 3]))
  }
})

# * 9.4 - Removing regressions that didn't run ----------------------------

# BMG
if (length(which(lapply(bmg_pred_data_by_sector, function(x) is.null(x)) == TRUE)) > 0) {
  bmg_pred_data_by_sector <- bmg_pred_data_by_sector[-which(lapply(bmg_pred_data_by_sector, function(x) is.null(x)) == TRUE)]
  bmg_pred_data_t_by_sector <- bmg_pred_data_t_by_sector[-which(lapply(bmg_pred_data_t_by_sector, function(x) is.null(x)) == TRUE)]
}

# no BMG
if (length(which(lapply(no_bmg_pred_data_by_sector, function(x) is.null(x)) == TRUE)) > 0) {
  no_bmg_pred_data_by_sector <- no_bmg_pred_data_by_sector[-which(lapply(no_bmg_pred_data_by_sector, function(x) is.null(x)) == TRUE)]
  bmg_pred_data_t_by_sector <- bmg_pred_data_t_by_sector[-which(lapply(bmg_pred_data_t_by_sector, function(x) is.null(x)) == TRUE)]
}

# * 9.5 - Final Output Table ----------------------------------------------

bmg_pred_data_by_sector <- tibble(
  Sector = names(bmg_pred_data_by_sector),
  bind_rows(bmg_pred_data_by_sector)
)

no_bmg_pred_data_by_sector <- tibble(
  Sector = names(no_bmg_pred_data_by_sector),
  bind_rows(no_bmg_pred_data_by_sector)
)

bmg_pred_data_t_by_sector <- tibble(
  Sector = names(bmg_pred_data_t_by_sector),
  bind_rows(bmg_pred_data_t_by_sector)
)

no_bmg_pred_data_t_by_sector <- tibble(
  Sector = names(no_bmg_pred_data_t_by_sector),
  bind_rows(no_bmg_pred_data_t_by_sector)
)

colnames(bmg_pred_data_by_sector)[2:9] <- c("FFB_Alpha", "FFB_BMG", "FFB_Mkt_less_RF", "FFB_SMB", "FFB_HML", "FFB_WML", "FFB_Rsq", "FFB_AdjRsq")
colnames(no_bmg_pred_data_by_sector)[2:8] <- c("FF_Alpha",  "FF_Mkt_less_RF", "FF_SMB", "FF_HML", "FF_WML","FF_Rsq", "FF_AdjRsq")


# * 9.6 - T-Statistic & Coefficient Row Binding ---------------------------

full_bmg_table_by_sector <- c()

# BMG by Sector Stats
for (j in 1:nrow(bmg_pred_data_by_sector)) {
  
  temp_t_holder <- cbind(bmg_pred_data_t_by_sector[j ,], 0, 0)
  colnames(temp_t_holder) <- colnames(bmg_pred_data_by_sector)
  
  temp_holder <- bind_rows(
    bmg_pred_data_by_sector[j, ],
    temp_t_holder
  ) %>%
    mutate(
      Statistic = c("Coefficient", "t-Stat")
    ) %>%
    relocate(Statistic, .after = Sector)
  
  full_bmg_table_by_sector <- bind_rows(
    full_bmg_table_by_sector,
    temp_holder
  )
  
}

full_bmg_table_by_sector <- full_bmg_table_by_sector %>%
  arrange(Sector, Statistic)

full_no_bmg_table_by_sector <- c()

# No BMG Stats by Sector
for (i in 1:nrow(bmg_pred_data_by_sector)) {
  temp_t_holder <- cbind(no_bmg_pred_data_t_by_sector[i ,], 0, 0)
  colnames(temp_t_holder) <- colnames(no_bmg_pred_data_by_sector)
  
  temp_holder <- bind_rows(
    no_bmg_pred_data_by_sector[i, ],
    temp_t_holder
  ) %>%
    mutate(
      Statistic = c("Coefficient", "t-Stat")
    ) %>%
    relocate(Statistic, .after = Sector)
  
  full_no_bmg_table_by_sector <- bind_rows(
    full_no_bmg_table_by_sector,
    temp_holder
  )
}

full_no_bmg_table_by_sector <- full_no_bmg_table_by_sector %>%
  arrange(Sector, Statistic)


# * 9.7 - Display the full table --------------------------------------------

full_bmg_table_by_sector
full_no_bmg_table_by_sector

# 9.8 - Write data ----------------------------------------------------------

write.csv(full_bmg_table_by_sector, "full_bmg_table.csv")
write.csv(full_no_bmg_table_by_sector, "full_no_bmg_table.csv")
