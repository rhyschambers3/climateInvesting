import argparse
from dateutil.relativedelta import relativedelta
import pandas as pd
import db
import get_stocks
import factor_regression
import input_function
import datetime


conn = db.get_db_connection()


def load_stocks_csv(filename):
    print('Loading stock tickers CSV {} ...'.format(filename))
    all_stock_data = pd.read_csv(filename, header=None)
    return all_stock_data.values


def load_carbon_data_from_db(factor_name):
    sql = '''SELECT
            date as "Date",
            bmg as "BMG"
        FROM carbon_risk_factor
        WHERE bmg_factor_name = %s
        ORDER BY date
        '''
    return pd.read_sql_query(sql, con=db.DB_CREDENTIALS,
                             index_col='Date', params=(factor_name,))


def load_ff_data_from_db():
    sql = '''SELECT
            date as "Date",
            mkt_rf as "Mkt-RF",
            smb as "SMB",
            hml as "HML",
            wml as "WML"
        FROM ff_factor
        ORDER BY date
        '''
    return pd.read_sql_query(sql, con=db.DB_CREDENTIALS,
                             index_col='Date')


def load_rf_data_from_db():
    sql = '''SELECT
            date as "Date",
            rf as "Rf"
        FROM risk_free
        ORDER BY date
        '''
    return pd.read_sql_query(sql, con=db.DB_CREDENTIALS,
                             index_col='Date')


def run_regression(ticker,
                   factor_name,
                   start_date,
                   end_date,
                   interval,
                   carbon_data=None,
                   ff_data=None,
                   rf_data=None,
                   verbose=False,
                   silent=False,
                   store=False,
                   from_db=False,
                   bulk=False):
    if carbon_data is None:
        carbon_data = load_carbon_data_from_db(factor_name)
        if verbose:
            print('Loaded carbon_data ...')
            print(carbon_data)
    elif verbose:
        print('Got carbon_data ...')
        print(carbon_data)
    if ff_data is None:
        ff_data = load_ff_data_from_db()
        if verbose:
            print('Loaded ff_data ...')
            print(ff_data)
    elif verbose:
        print('Got ff_data ...')
        print(ff_data)
    if rf_data is None:
        rf_data = load_rf_data_from_db()
        if verbose:
            print('Loaded rf_data ...')
            print(rf_data)
    elif verbose:
        print('Got risk-fre rate')
        print(rf_data)

    if from_db:
        stock_data = get_stocks.load_stocks_from_db(ticker)
        stock_data = input_function.convert_to_form_db(stock_data)
    else:
        stock_data = get_stocks.import_stock(ticker)

    if verbose:
        print(stock_data)

    if stock_data is None or len(stock_data) == 0:
        print('No stock data for {} !'.format(ticker))
        return
    # convert to pct change
    stock_data = stock_data.pct_change(periods=1)

    if bulk is False:
        run_regression_internal(stock_data, carbon_data, ff_data, rf_data,
                                ticker, factor_name, start_date, end_date, interval, verbose, silent, store)
    else:
        ff_data = ff_data/100
        rf_data = rf_data/100
        all_factor_df = factor_regression.merge_data(stock_data, carbon_data)
        all_factor_df = factor_regression.merge_data(all_factor_df, ff_data)
        all_factor_df = factor_regression.merge_data(all_factor_df, rf_data)
        all_factor_df['Close'] = all_factor_df['Close'] - all_factor_df['Rf']
        all_factor_df = all_factor_df.drop(['Rf'], axis=1)
        run_regression_internal_bulk(
            all_factor_df, ticker, factor_name, start_date, end_date, interval, verbose, silent, store)


def run_regression_internal_bulk(all_data,
                                 ticker,
                                 factor_name,
                                 start_date,
                                 end_date,
                                 interval,
                                 verbose,
                                 silent,
                                 store):
    try:
        if start_date:
            start_date = pd.Period(start_date, freq='M').end_time.date()
            start_date = factor_regression.parse_date('Start', start_date)
        else:
            # use the common start date of all series:
            start_date = min(all_data.index)

        interval_dt = relativedelta(months=interval)
        if end_date:
            end_date = pd.Period(end_date, freq='M').end_time.date()
            end_date = factor_regression.parse_date('End Date', end_date)
        else:
            # use the common end date of all series:
            end_date = max(all_data.index)
        r_end_date = start_date+interval_dt
        r_end_date = pd.Period(r_end_date, freq='M').end_time.date()
        if r_end_date > end_date:
            print('!! Done running regression on stock {} from {} to {} (next regression would end in {})'.format(
                ticker, start_date, end_date, r_end_date))
            return
        start_date += datetime.timedelta(days=1)
        start_date, r_end_date, data_start_date, data_end_date, model_output, coef_df_simple = factor_regression.run_regression_bulk(
            all_data, ticker, start_date, end_date=r_end_date, verbose=verbose, silent=silent)
        if verbose:
            print("-- {} ran regression start={} end={} data_start={} data_end={} wanted_end={}".format(
                ticker, start_date, r_end_date, data_start_date, data_end_date, end_date))
    except factor_regression.DateInRangeError as e:
        print('!! Error running regression on stock {} from {} to {}: {}'.format(
            ticker, start_date, end_date, e))
        return
    except ValueError as e:
        print('!! Error running regression on stock {} from {} to {}: {}'.format(
            ticker, start_date, end_date, e))
        return

    if model_output is False:
        print('!! Error running regression on stock {} from {} to {}'.format(
            ticker, start_date, end_date))
        return

    # stop running when the data_end_date is > end_date (we no longer have enough data)
    if data_end_date > end_date:
        print('!! Finished running regression on stock {} from {} to {} (data ends in {})'.format(
            ticker, start_date, end_date, data_end_date))
        return

    if store:
        print('Ran regression for {} from {} to {} ...'.format(
            ticker, start_date, r_end_date))
        # store results in the DB
        fields = ['Constant', 'BMG', 'Mkt-RF', 'SMB', 'HML', 'WML',
                  'Jarque-Bera', 'Breusch-Pagan', 'Durbin-Watson', 'R Squared']
        index_to_sql_dict = {
            'std err': '_std_error',
            't': '_t_stat',
            'P>|t|': '_p_gt_abs_t',
        }
        sql_params = {
            'ticker': ticker,
            'bmg_factor_name': factor_name,
            'from_date': start_date,
            'thru_date': r_end_date,
            'data_from_date': data_start_date,
            'data_thru_date': data_end_date,
        }
        for index, row in coef_df_simple.iterrows():
            for f in fields:
                sql_field = f.lower().replace(' ', '_').replace('-', '_')
                if index != 'coef':
                    sql_field += index_to_sql_dict[index]
                if row[f] is not None and row[f] != '':
                    sql_params[sql_field] = row[f]
        store_regression_into_db(sql_params)

    # recurse the new interval
    dt = relativedelta(months=1)
    start_date -= datetime.timedelta(days=1)
    run_regression_internal_bulk(all_data, ticker, start_date+dt,
                                 end_date, interval, verbose, silent, store)


def run_regression_internal(stock_data,
                            carbon_data,
                            ff_data,
                            rf_data,
                            ticker,
                            factor_name,
                            start_date,
                            end_date,
                            interval,
                            verbose,
                            silent,
                            store):
    try:
        if start_date:
            start_date = pd.Period(start_date, freq='M').end_time.date()
            start_date = factor_regression.parse_date('Start', start_date)
        else:
            # use the common start date of all series:
            start_date = max(min(stock_data.index), min(
                carbon_data.index), min(ff_data.index), min(rf_data.index))

        interval_dt = relativedelta(months=interval)
        if end_date:
            end_date = pd.Period(end_date, freq='M').end_time.date()
            end_date = factor_regression.parse_date('End Date', end_date)
        else:
            # use the common end date of all series:
            end_date = min(max(stock_data.index), max(
                carbon_data.index), max(ff_data.index), max(rf_data.index))
        r_end_date = start_date+interval_dt
        r_end_date = pd.Period(r_end_date, freq='M').end_time.date()
        if r_end_date > end_date:
            print('!! Done running regression on stock {} from {} to {} (next regression would end in {})'.format(
                ticker, start_date, end_date, r_end_date))
            return
        start_date += datetime.timedelta(days=1)
        start_date, r_end_date, data_start_date, data_end_date, model_output, coef_df_simple = factor_regression.run_regression(
            stock_data, carbon_data, ff_data, rf_data, ticker, start_date, end_date=r_end_date, verbose=verbose, silent=silent)
        if verbose:
            print("-- {} ran regression start={} end={} data_start={} data_end={} wanted_end={}".format(
                ticker, start_date, r_end_date, data_start_date, data_end_date, end_date))
    except factor_regression.DateInRangeError as e:
        print('!! Error running regression on stock {} from {} to {}: {}'.format(
            ticker, start_date, end_date, e))
        return
    except ValueError as e:
        print('!! Error running regression on stock {} from {} to {}: {}'.format(
            ticker, start_date, end_date, e))
        return

    if model_output is False:
        print('!! Error running regression on stock {} from {} to {}'.format(
            ticker, start_date, end_date))
        return

    # stop running when the data_end_date is > end_date (we no longer have enough data)
    if data_end_date > end_date:
        print('!! Finished running regression on stock {} from {} to {} (data ends in {})'.format(
            ticker, start_date, end_date, data_end_date))
        return

    if store:
        print('Ran regression for {} from {} to {} ...'.format(
            ticker, start_date, r_end_date))
        # store results in the DB
        fields = ['Constant', 'BMG', 'Mkt-RF', 'SMB', 'HML', 'WML',
                  'Jarque-Bera', 'Breusch-Pagan', 'Durbin-Watson', 'R Squared']
        index_to_sql_dict = {
            'std err': '_std_error',
            't': '_t_stat',
            'P>|t|': '_p_gt_abs_t',
        }
        sql_params = {
            'ticker': ticker,
            'bmg_factor_name': factor_name,
            'from_date': start_date,
            'thru_date': r_end_date,
            'data_from_date': data_start_date,
            'data_thru_date': data_end_date,
        }
        for index, row in coef_df_simple.iterrows():
            for f in fields:
                sql_field = f.lower().replace(' ', '_').replace('-', '_')
                if index != 'coef':
                    sql_field += index_to_sql_dict[index]
                if row[f] is not None and row[f] != '':
                    sql_params[sql_field] = row[f]
        store_regression_into_db(sql_params)

    # recurse the new interval
    dt = relativedelta(months=1)
    start_date -= datetime.timedelta(days=1)
    run_regression_internal(stock_data, carbon_data, ff_data, rf_data,
                            ticker, factor_name, start_date+dt, end_date, interval, verbose, silent, store)


def store_regression_into_db(sql_params):
    del_sql = '''DELETE FROM stock_stats WHERE ticker = %s and bmg_factor_name = %s and from_date = %s and thru_date = %s;'''
    placeholder = ", ".join(["%s"] * len(sql_params))
    stmt = "INSERT INTO stock_stats ({columns}) values ({values});".format(
        columns=",".join(sql_params.keys()), values=placeholder)
    with conn.cursor() as cursor:
        cursor.execute(
            del_sql, (sql_params['ticker'], sql_params['bmg_factor_name'], sql_params['from_date'], sql_params['thru_date']))
        cursor.execute(stmt, list(sql_params.values()))


def main(args):
    start_time = datetime.datetime.now()
    if args.ticker:
        run_regression(ticker=args.ticker,
                       factor_name=args.bmg_factor_name,
                       start_date=args.start_date,
                       end_date=args.end_date,
                       interval=args.interval,
                       verbose=args.verbose,
                       store=(not args.dryrun),
                       silent=(not args.dryrun),
                       from_db=args.stocks_from_db,
                       bulk=args.bulk_regression)
    elif args.file:
        carbon_data = load_carbon_data_from_db(args.bmg_factor_name)
        ff_data = load_ff_data_from_db()
        rf_data = load_rf_data_from_db()
        stocks = load_stocks_csv(args.file)
        for i in range(0, len(stocks)):
            stock_name = stocks[i].item()
            print('* running regression for {} ... '.format(stock_name))
            run_regression(stock_name, factor_name=args.bmg_factor_name, start_date=args.start_date, end_date=args.end_date, interval=args.interval, carbon_data=carbon_data,
                           ff_data=ff_data, rf_data=rf_data, verbose=args.verbose, silent=(not args.dryrun), store=(not args.dryrun), from_db=args.stock_from_db, bulk=args.bulk_regression)
    else:
        carbon_data = load_carbon_data_from_db(args.bmg_factor_name)
        ff_data = load_ff_data_from_db()
        rf_data = load_rf_data_from_db()
        stocks = get_stocks.load_stocks_defined_in_db()
        for i in range(0, len(stocks)):
            stock_name = stocks[i]
            print('* running regression for {} ... '.format(stock_name))
            run_regression(stock_name, factor_name=args.bmg_factor_name, start_date=args.start_date, end_date=args.end_date, interval=args.interval, carbon_data=carbon_data,
                           ff_data=ff_data, rf_data=rf_data, verbose=args.verbose, silent=(not args.dryrun), store=(not args.dryrun), bulk=args.bulk_regression)
    end_time = datetime.datetime.now()
    print(end_time - start_time)


# run
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--from_db", action='store_true',
                        help="import of tickers in the stocks table of the Database instead of using a CSV file, this is the default unless -t or -f is used")
    parser.add_argument("-f", "--file",
                        help="specify the CSV file of stock tickers to import")
    parser.add_argument("-t", "--ticker",
                        help="specify a single ticker to run the regression for, ignores the CSV file")
    parser.add_argument("-o", "--dryrun", action='store_true',
                        help="Only shows the results, do not store the results in the DB")
    parser.add_argument("-s", "--start_date",
                        help="Sets the start date for the regression, must be in the YYYY-MM-DD format, defaults to the start date of all the data series for a given stock")
    parser.add_argument("-e", "--end_date",
                        help="Sets the end date for the regression, must be in the YYYY-MM-DD format, defaults to the last date of all the data series for a given stock")
    parser.add_argument("-i", "--interval", default=60, type=int,
                        help="Sets number of months for the regresssion interval, defaults to 60")
    parser.add_argument("-c", "--bmg_factor_name", default='DEFAULT',
                        help="Sets the factor name of the carbon_risk_factor used")
    parser.add_argument("-v", "--verbose", action='store_true',
                        help="More verbose output")
    parser.add_argument("-sd", "--stock_from_db", default=False, action='store_true',
                        help="Import stock data from the DB instead of downloading")
    parser.add_argument("-b", "--bulk_regression", action='store_true',
                        help="Run bulk regression that should run faster")
    main(parser.parse_args())
