library(tidyverse)

get_dataframe_dimensions <- function(x) {
  dim = dim(x)
  return(dim)
}

mass_regression <- function(stock_data,
                            stock_col_name,
                            reg_formulas) {
  
  stock_reg_data <- list()
  
  stock_names <- stock_data %>%
    select(stock_col_name) %>%
    distinct()
  
  for (i in 1:nrow(stock_names)) {
    ind_stock_name <- as.character(stock_names[i, 1])
    print(paste0(i, ": ", ind_stock_name))
    ind_stock_data <- stock_data[which(stock_data[stock_col_name] == ind_stock_name), ]
    for (j in 1:length(reg_formulas)) {
      j_reg_formula <- as.formula(reg_formulas[j])
      j_reg_results <- lm(j_reg_formula, ind_stock_data)
      stock_reg_data[[ind_stock_name]][["Regression"]][[j]] <- j_reg_results
      stock_reg_data[[ind_stock_name]][["Data"]][[j]] <- ind_stock_data
    }
  }
 
  return(stock_reg_data)
}

get_data_output <- function(x, reg_num) {
  residuals <- lapply(x, function(x) {x[["Regression"]][[reg_num]]$residuals})
  x_data = lapply(x, function(x) {x[["Data"]][[reg_num]]})
  flatten_residuals <- data.frame(grp=rep(names(residuals), lengths(residuals)), num=unlist(residuals), row.names = NULL)
  flatten_data <- bind_rows(x_data)
  return(list(residuals = flatten_residuals,
              data = flatten_data))
}