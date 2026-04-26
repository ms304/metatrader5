//+------------------------------------------------------------------+
//|                                       IchimokuBreakoutScanner.mq5|
//|                                Copyright 2024, Reuniware Systems |
//|                                     https://github.com/reuniware |
//| Scans all MarketWatch symbols on the current chart timeframe.    |
//| SSB strict crossover only — candles -2 and -1 (both closed)     |
//| Bullish : close[-2] < SSB  &&  close[-1] > SSB                  |
//| Bearish : close[-2] > SSB  &&  close[-1] < SSB                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Reuniware Systems"
#property link      "https://github.com/reuniware"
#property version   "1.04"
#property strict

input double lot_size             = 0.1;   // Fixed lot size
input double take_profit_percent  = 1.0;   // Take profit in percent
input double stop_loss_percent    = 1.0;   // Stop loss in percent
input int    senkou_span_b_period = 52;    // Period for Senkou Span B
input bool   trade_on_signal      = false; // Open trades automatically on signal

bool g_scan_running = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_scan_running = false;
   Print("IchimokuBreakoutScanner v1.04 initialized — SSB strict crossover [-2,-1] — TF=",
         EnumToString((ENUM_TIMEFRAMES)Period()));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_scan_running = false;
   Comment("");
   Print("IchimokuBreakoutScanner deinitialized — reason=", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if (g_scan_running) return;
   g_scan_running = true;

   ENUM_TIMEFRAMES timeframe     = (ENUM_TIMEFRAMES)Period();
   int             total_symbols = SymbolsTotal(true);
   datetime        scan_start    = TimeCurrent();

   int    count_bull    = 0;
   int    count_bear    = 0;
   int    count_scanned = 0;
   string alert_lines   = "";

   for (int i = 0; i < total_symbols; i++)
     {
      string sym = SymbolName(i, true);
      if (sym == "") continue;

      double close_2 = iClose(sym, timeframe, 2); // bougie -2 clôturée
      double close_1 = iClose(sym, timeframe, 1); // bougie -1 clôturée

      if (close_1 == 0 || close_2 == 0) continue;

      double ssb = CalculateSenkouSpanB(sym, timeframe, senkou_span_b_period);
      if (ssb == 0) continue;

      count_scanned++;

      // --- Franchissement haussier strict ---
      // close[-2] strictement sous SSB ET close[-1] strictement au-dessus
      bool bull = close_2 < ssb && close_1 > ssb;

      // --- Franchissement baissier strict ---
      // close[-2] strictement au-dessus SSB ET close[-1] strictement en-dessous
      bool bear = close_2 > ssb && close_1 < ssb;

      if (bull)
        {
         count_bull++;
         string msg = "SSB BULL | " + sym +
                      " | close-2=" + DoubleToString(close_2, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) +
                      " close-1="   + DoubleToString(close_1, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) +
                      " SSB="       + DoubleToString(ssb,     (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
         Print(msg);
         Alert(msg);
         alert_lines += "▲ " + sym + " SSB BULL\n";

         if (trade_on_signal && !PositionSelect(sym))
           {
            double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
            OpenPosition(sym, ORDER_TYPE_BUY, ask);
           }
        }

      if (bear)
        {
         count_bear++;
         string msg = "SSB BEAR | " + sym +
                      " | close-2=" + DoubleToString(close_2, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) +
                      " close-1="   + DoubleToString(close_1, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) +
                      " SSB="       + DoubleToString(ssb,     (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
         Print(msg);
         Alert(msg);
         alert_lines += "▼ " + sym + " SSB BEAR\n";

         if (trade_on_signal && !PositionSelect(sym))
           {
            double bid = SymbolInfoDouble(sym, SYMBOL_BID);
            OpenPosition(sym, ORDER_TYPE_SELL, bid);
           }
        }

      // --- Gestion TP/SL ---
      if (trade_on_signal && PositionSelect(sym))
        {
         double pos_open   = PositionGetDouble(POSITION_PRICE_OPEN);
         double bid_price  = SymbolInfoDouble(sym, SYMBOL_BID);
         double profit_pct = (bid_price - pos_open) / pos_open * 100;

         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            profit_pct = -profit_pct;

         if (profit_pct >= take_profit_percent || profit_pct <= -stop_loss_percent)
            ClosePosition(sym);
        }
     }

   // --- Log de fin de cycle ---
   datetime scan_end      = TimeCurrent();
   int      scan_duration = (int)(scan_end - scan_start);

   Print(StringFormat(
      "[SCAN DONE] TF=%s | Scanned=%d/%d | Bull=%d | Bear=%d | Duration=%ds",
      EnumToString(timeframe), count_scanned, total_symbols,
      count_bull, count_bear, scan_duration));

   string display = "=== ICHIMOKU SSB SCANNER v1.04 ===\n" +
                    "TF      : " + EnumToString(timeframe) + "\n" +
                    "Scannés : " + IntegerToString(count_scanned) + "/" + IntegerToString(total_symbols) + "\n" +
                    "Scan    : " + TimeToString(scan_end, TIME_DATE|TIME_MINUTES) + "\n";

   display += (alert_lines != "") ? "\n" + alert_lines : "\nAucun franchissement SSB\n";

   Comment(display);

   g_scan_running = false;
  }

//+------------------------------------------------------------------+
//| Open a position                                                  |
//+------------------------------------------------------------------+
void OpenPosition(string sym, ENUM_ORDER_TYPE order_type, double price)
  {
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = sym;
   request.volume       = NormalizeVolume(lot_size, sym);
   request.type         = order_type;
   request.price        = price;
   request.deviation    = 10;
   request.type_filling = ORDER_FILLING_FOK;
   request.type_time    = ORDER_TIME_GTC;

   if (order_type == ORDER_TYPE_BUY)
     {
      request.tp = price * (1 + take_profit_percent / 100);
      request.sl = price * (1 - stop_loss_percent   / 100);
     }
   else
     {
      request.tp = price * (1 - take_profit_percent / 100);
      request.sl = price * (1 + stop_loss_percent   / 100);
     }

   if (OrderSend(request, result))
     {
      if (result.retcode == TRADE_RETCODE_DONE)
         Print("Position opened | ", sym, " | ", EnumToString(order_type),
               " @ ", price, " | TP=", request.tp, " SL=", request.sl);
      else
         Print("Failed to open | ", sym, " | Error=", result.retcode);
     }
   else
      Print("OrderSend failed | ", sym, " | Error=", GetLastError());
  }

//+------------------------------------------------------------------+
//| Close a position                                                 |
//+------------------------------------------------------------------+
void ClosePosition(string sym)
  {
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   double close_price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                        ? SymbolInfoDouble(sym, SYMBOL_BID)
                        : SymbolInfoDouble(sym, SYMBOL_ASK);

   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = sym;
   request.volume       = PositionGetDouble(POSITION_VOLUME);
   request.type         = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                          ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price        = close_price;
   request.deviation    = 10;
   request.type_filling = ORDER_FILLING_FOK;
   request.type_time    = ORDER_TIME_GTC;
   request.position     = PositionGetInteger(POSITION_TICKET);

   if (OrderSend(request, result))
     {
      if (result.retcode == TRADE_RETCODE_DONE)
         Print("Position closed | ", sym, " @ ", close_price);
      else
         Print("Failed to close | ", sym, " | Error=", result.retcode);
     }
   else
      Print("OrderSend failed | ", sym, " | Error=", GetLastError());
  }

//+------------------------------------------------------------------+
//| Normalize volume                                                 |
//+------------------------------------------------------------------+
double NormalizeVolume(double volume, string symbol)
  {
   double min_volume   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_volume   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double volume_step  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   int    steps             = (int)MathRound((volume - min_volume) / volume_step);
   double normalized_volume = min_volume + steps * volume_step;

   if (normalized_volume > max_volume) normalized_volume = max_volume;
   return normalized_volume;
  }

//+------------------------------------------------------------------+
//| Calculate Senkou Span B                                          |
//+------------------------------------------------------------------+
double CalculateSenkouSpanB(string symbol, ENUM_TIMEFRAMES timeframe, int period)
  {
   double highest_high = iHigh(symbol, timeframe, iHighest(symbol, timeframe, MODE_HIGH, period, 1));
   double lowest_low   = iLow(symbol,  timeframe, iLowest(symbol,  timeframe, MODE_LOW,  period, 1));
   return (highest_high + lowest_low) / 2;
  }
//+------------------------------------------------------------------+
