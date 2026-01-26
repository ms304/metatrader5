//+------------------------------------------------------------------+
//|                                     ICT_Silver_Bullet_Scanner.mq5 |
//|                                     Copyright 2026, Silver Bullet Logic   |
//|                                             Based on ICT Concepts         |
//+------------------------------------------------------------------+
#property copyright "mc0d3 t0w3rbu5t3r"
#property link      ""
#property version   "1.00"
#property strict

//--- INPUTS ---
// Note: J'ai retiré le groupe "Time Settings" car le scan est désormais manuel/continu.

input group "Scanner Settings"
input ENUM_TIMEFRAMES InpTimeframe  = PERIOD_M5; // Timeframe to Scan (M1, M5 recommended)
input double   InpMinFVGSizePoints  = 1.0;       // Minimum Gap Size (Points) to trigger alert

input group "Alerts"
input bool     InpAlertPopUp        = true;  // Alert: Pop-up Window
input bool     InpAlertPush         = true;  // Alert: Mobile Push Notification
input bool     InpAlertSound        = true;  // Alert: Sound

// Structure to track alerts so we don't spam the same bar
struct SymbolState {
   string symbol;
   datetime lastAlertBarTime;
};
SymbolState alertHistory[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("--- ICT SILVER BULLET CONTINUOUS SCANNER STARTED ---");
   Print("Scanning timeframe: ", EnumToString(InpTimeframe));
   Print("Time filters removed. Scanning all Market Watch symbols continuously.");
   
   // Set Timer to scan every 5 seconds
   EventSetTimer(5);
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//| Timer event function (The Scanner Loop)                          |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // 1. Loop through Market Watch Symbols
   // No time check anymore. It runs every time the timer ticks.
   
   int total = SymbolsTotal(true); // true = only visible in Market Watch
   
   for(int i = 0; i < total; i++)
     {
      string symbol = SymbolName(i, true);
      ScanSymbolForRealTimeFVG(symbol);
     }
  }

//+------------------------------------------------------------------+
//| Logic to Detect FVG (REAL-TIME / DURING FORMATION)               |
//+------------------------------------------------------------------+
void ScanSymbolForRealTimeFVG(string symbol)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // Get last 3 candles.
   // Index 0 = Current Live Candle (Candle 3)
   // Index 1 = Previous Closed Candle (Displacement)
   // Index 2 = Origin Candle (Candle 1)
   if(CopyRates(symbol, InpTimeframe, 0, 3, rates) < 3) return;
   
   // Check history to prevent spamming alerts for the same candle
   if(IsAlreadyAlerted(symbol, rates[0].time)) return;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   // --- BULLISH FVG LOGIC ---
   // We look for a gap between Candle 1 High and Current Candle Low
   // Pattern: [Candle 1 High] < GAP < [Current Candle Low]
   if(rates[2].high < rates[0].low) 
     {
      double gapSize = rates[0].low - rates[2].high;
      
      // Filter by minimum size
      if(gapSize >= InpMinFVGSizePoints * point)
        {
         string msg = "🟢 BULLISH Silver Bullet Setup\n" + 
                      symbol + " (" + EnumToString(InpTimeframe) + ")\n" +
                      "FVG forming NOW (Real-Time).";
         
         SendAlerts(msg);
         AddToHistory(symbol, rates[0].time);
        }
     }

   // --- BEARISH FVG LOGIC ---
   // We look for a gap between Candle 1 Low and Current Candle High
   // Pattern: [Current Candle High] < GAP < [Candle 1 Low]
   if(rates[2].low > rates[0].high) 
     {
      double gapSize = rates[2].low - rates[0].high;
      
      // Filter by minimum size
      if(gapSize >= InpMinFVGSizePoints * point)
        {
         string msg = "🔴 BEARISH Silver Bullet Setup\n" + 
                      symbol + " (" + EnumToString(InpTimeframe) + ")\n" +
                      "FVG forming NOW (Real-Time).";
         
         SendAlerts(msg);
         AddToHistory(symbol, rates[0].time);
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: Prevent duplicate alerts for the same bar time           |
//+------------------------------------------------------------------+
bool IsAlreadyAlerted(string symbol, datetime time)
  {
   for(int i=0; i<ArraySize(alertHistory); i++)
     {
      if(alertHistory[i].symbol == symbol)
        {
         // If we matched symbol and time, we already alerted
         if(alertHistory[i].lastAlertBarTime == time) return true;
         return false; // Symbol found but time is new, so not alerted yet
        }
     }
   return false; // Symbol not in history
  }

void AddToHistory(string symbol, datetime time)
  {
   // Update existing symbol entry
   for(int i=0; i<ArraySize(alertHistory); i++)
     {
      if(alertHistory[i].symbol == symbol)
        {
         alertHistory[i].lastAlertBarTime = time;
         return;
        }
     }
   
   // Add new symbol entry
   int size = ArraySize(alertHistory);
   ArrayResize(alertHistory, size + 1);
   alertHistory[size].symbol = symbol;
   alertHistory[size].lastAlertBarTime = time;
  }

//+------------------------------------------------------------------+
//| Helper: Send user selected alerts                                |
//+------------------------------------------------------------------+
void SendAlerts(string msg)
  {
   if(InpAlertPopUp) Alert(msg);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertSound) PlaySound("alert.wav");
  }
//+------------------------------------------------------------------+
