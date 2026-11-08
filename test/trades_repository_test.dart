import 'package:flutter_test/flutter_test.dart';
import 'package:my_market_lab/core/format.dart';
import 'package:my_market_lab/data/repositories/trades_repository.dart';

Map<String, Object?> validTrade({String status = 'open'}) => {
      'account_type': 'demo',
      'instrument': 'XAUUSD',
      'direction': 'long',
      'currency_code': 'EUR',
      'size_unit': 'lots',
      'status': status,
      'opened_at': '2026-10-30T09:00:00.000Z',
      'closed_at': status == 'closed' ? '2026-10-30T10:00:00.000Z' : null,
      'entry_price': 2000.0,
      'exit_price': status == 'closed' ? 2010.0 : null,
      'stop_price': 1990.0,
      'target_price': 2020.0,
      'size': 0.1,
      'initial_risk_minor': 1000,
      'gross_pnl_minor': status == 'closed' ? 2000 : null,
      'costs_minor': 100,
    };

void main() {
  test('accepts an open trade with actual entry and explicit volume/currency',
      () {
    expect(validateTradeValues(validTrade()), isNull);
  });

  test(
      'closed trade requires exit, close time, and explicitly recorded gross P/L',
      () {
    final trade = validTrade(status: 'closed');

    expect(validateTradeValues({...trade, 'exit_price': null}),
        contains('exit price'));
    expect(validateTradeValues({...trade, 'closed_at': null}),
        contains('closing date'));
    expect(validateTradeValues({...trade, 'gross_pnl_minor': null}),
        contains('gross P/L'));
  });

  test('rejects invalid prices, volume, costs, and missing units or currency',
      () {
    final trade = validTrade();

    expect(validateTradeValues({...trade, 'entry_price': 0}),
        contains('entry price'));
    expect(validateTradeValues({...trade, 'size': -1}),
        contains('position volume'));
    expect(validateTradeValues({...trade, 'costs_minor': -1}),
        contains('Trading costs'));
    expect(validateTradeValues({...trade, 'size_unit': null}),
        contains('volume unit'));
    expect(validateTradeValues({...trade, 'currency_code': null}),
        contains('account currency'));
  });

  test('preserves unknown currency and unit on legacy records', () {
    final legacy = {...validTrade(), 'currency_code': null, 'size_unit': null};

    expect(
      validateTradeValues(
        legacy,
        allowMissingCurrency: true,
        allowMissingSizeUnit: true,
      ),
      isNull,
    );
  });

  test('an open trade is not reported as realised net P/L', () {
    expect(
      netMinor({
        'status': 'open',
        'closed_at': '2026-10-30T10:00:00.000Z',
        'entry_price': 2000.0,
        'exit_price': 2010.0,
        'size': 0.1,
        'gross_pnl_minor': 2000,
        'costs_minor': 100,
      }),
      isNull,
    );
  });

  test('closed net P/L subtracts costs from recorded gross P/L', () {
    expect(
      netMinor({
        'status': 'closed',
        'closed_at': '2026-10-30T10:00:00.000Z',
        'entry_price': 2000.0,
        'exit_price': 2010.0,
        'size': 0.1,
        'gross_pnl_minor': 2000,
        'costs_minor': 100,
      }),
      1900,
    );
  });

  test('money input and display use the selected currency minor-unit precision',
      () {
    expect(currencyFractionDigits('JPY'), 0);
    expect(
        parseMinor('125', fractionDigits: currencyFractionDigits('JPY')), 125);
    expect(parseMinor('125.50', fractionDigits: currencyFractionDigits('JPY')),
        isNull);
    expect(
        formatMinor(125, fractionDigits: currencyFractionDigits('JPY')), '125');
    expect(currencyFractionDigits('KWD'), 3);
    expect(parseMinor('1.234', fractionDigits: currencyFractionDigits('KWD')),
        1234);
    expect(formatMinor(1234, fractionDigits: currencyFractionDigits('KWD')),
        '1.234');
  });
}
