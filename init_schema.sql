DROP TABLE IF EXISTS carbon_risk_factor CASCADE;

CREATE TABLE carbon_risk_factor (
    date date primary key,
    bmg decimal(12, 10)
);

DROP TABLE IF EXISTS ff_factor CASCADE;

CREATE TABLE ff_factor (
    date date primary key,
    mkt_rf decimal(8, 5),
    smb decimal(8, 5),
    hml decimal(8, 5),
    wml decimal(8, 5)
);


DROP TABLE IF EXISTS stocks CASCADE;
CREATE TABLE stocks (
    ticker text,
    name text,
    sector text,
    sub_sector text,
    PRIMARY KEY (ticker)
);


DROP TABLE IF EXISTS stock_components CASCADE;
CREATE TABLE stock_components (
    ticker text,
    component_stock text REFERENCES stocks (ticker),
    percentage decimal(8, 5),
    PRIMARY KEY (ticker, component_stock)
);


DROP TABLE IF EXISTS stock_data CASCADE;
CREATE TABLE stock_data (
    ticker text,
    date date,
    close decimal(30, 10),
    return decimal(20, 10),
    PRIMARY KEY (ticker, date)
);

DROP TABLE IF EXISTS stock_stats CASCADE;
CREATE TABLE stock_stats (
    ticker text,
    from_date date,
    thru_date date,
    data_from_date date,
    data_thru_date date,
    constant decimal(8, 5),
    constant_std_error decimal(8, 5),
    constant_t_stat decimal(8, 5),
    constant_p_gt_abs_t decimal(8, 5),
    bmg decimal(8, 5),
    bmg_std_error decimal(8, 5),
    bmg_t_stat decimal(8, 5),
    bmg_p_gt_abs_t decimal(8, 5),
    mkt_rf decimal(8, 5),
    mkt_rf_std_error decimal(8, 5),
    mkt_rf_t_stat decimal(8, 5),
    mkt_rf_p_gt_abs_t decimal(8, 5),
    smb decimal(8, 5),
    smb_std_error decimal(8, 5),
    smb_t_stat decimal(8, 5),
    smb_p_gt_abs_t decimal(8, 5),
    hml decimal(8, 5),
    hml_std_error decimal(8, 5),
    hml_t_stat decimal(8, 5),
    hml_p_gt_abs_t decimal(8, 5),
    wml decimal(8, 5),
    wml_std_error decimal(8, 5),
    wml_t_stat decimal(8, 5),
    wml_p_gt_abs_t decimal(8, 5),
    jarque_bera decimal(8, 5),
    jarque_bera_p_gt_abs_t decimal(8, 5),
    breusch_pagan decimal(8, 5),
    breusch_pagan_p_gt_abs_t decimal(8, 5),
    durbin_watson decimal(8, 5),
    r_squared decimal(8, 5),
    PRIMARY KEY (ticker, from_date, thru_date)
);