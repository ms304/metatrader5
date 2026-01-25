//+------------------------------------------------------------------+
//|                                             ICT_Silver_Bullet_Scanner.mq5 |
//|                                     Copyright 2026, Silver Bullet Logic   |
//|                                             Based on ICT Concepts         |
//+------------------------------------------------------------------+
#property copyright "t0w3rbu5t3r"
#property link      ""
#property version   "1.00"
#property strict

//--- INPUTS
input group "Time Settings"
input int      InpBrokerHourFor10AM = 17;    // What hour is it on your Broker when it is 10:00 AM New York?
input ENUM_TIMEFRAMES InpTimeframe  = PERIOD_M5; // Timeframe to Scan (M1 or M5 recommended)

input group "Setup Configuration"
input double   InpMinFVGSizePoints  = 1.0;   // Minimum FVG size (in Points/Pips) to trigger alert

input group "Alerts"
input bool     InpAlertPopUp        = true;  // Alert: Pop-up Window
input bool     InpAlertPush         = true;  // Alert: Mobile Push Notification
input bool     InpAlertSound        = false; // Alert: Sound

//--- GLOBAL VARIABLES
int NY_3AM_Hour;
int NY_10AM_Hour;
int NY_2PM_Hour;

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
   // Calculate the Broker Hours for the Silver Bullet Windows based on user reference
   // User inputs the hour for 10AM NY. 
   // 3 AM NY is 7 hours before 10 AM.
   // 2 PM (14:00) NY is 4 hours after 10 AM.
   
   NY_10AM_Hour = InpBrokerHourFor10AM;
   NY_3AM_Hour  = InpBrokerHourFor10AM - 7;
   NY_2PM_Hour  = InpBrokerHourFor10AM + 4;
   
   // Handle day rollover (if 3AM is previous day in broker time, though rare for standard UTC+2/3)
   if(NY_3AM_Hour < 0) NY_3AM_Hour += 24;
   if(NY_2PM_Hour >= 24) NY_2PM_Hour -= 24;

   Print("--- ICT SILVER BULLET SCANNER STARTED ---");
   Print("Scanning for 3 AM NY Session at Broker Hour: ", NY_3AM_Hour);
   Print("Scanning for 10 AM NY Session at Broker Hour: ", NY_10AM_Hour);
   Print("Scanning for 2 PM NY Session at Broker Hour: ", NY_2PM_Hour);
   
   // Initialize Timer to scan every 10 seconds
   EventSetTimer(10);
   
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
   // 1. Check if we are currently in a Silver Bullet Hour
   datetime currentTime = TimeCurrent();
   MqlDateTime tm;
   TimeToStruct(currentTime, tm);
   
   bool isSilverBullet = false;
   string sessionName = "";
   
   if(tm.hour == NY_3AM_Hour) {
      isSilverBullet = true;
      sessionName = "London Open SB";
   }
   else if(tm.hour == NY_10AM_Hour) {
      isSilverBullet = true;
      sessionName = "AM Session SB";
   }
   else if(tm.hour == NY_2PM_Hour) {
      isSilverBullet = true;
      sessionName = "PM Session SB";
   }
   
   if(!isSilverBullet) return; // Exit if not in the time window

   // 2. Loop through Market Watch Symbols
   int total = SymbolsTotal(true); // true = only visible in Market Watch
   
   for(int i = 0; i < total; i++)
     {
      string symbol = SymbolName(i, true);
      ScanSymbolForFVG(symbol, sessionName);
     }
  }

//+------------------------------------------------------------------+
//| Logic to Detect FVG                                              |
//+------------------------------------------------------------------+
void ScanSymbolForFVG(string symbol, string session)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // Get last 4 candles. Index 0 is currently forming. Index 1, 2, 3 make the potential FVG.
   // We scan based on Completed Candles (1, 2, 3)
   if(CopyRates(symbol, InpTimeframe, 0, 4, rates) < 4) return;
   
   // We check if we already alerted this specific bar for this symbol
   if(IsAlreadyAlerted(symbol, rates[1].time)) return;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   // --- BULLISH FVG LOGIC ---
   // Candle 3 High < Candle 1 Low (Gap exists)
   // Candle 2 is the displacement candle
   if(rates[3].high < rates[1].low)
     {
      double gapSize = rates[1].low - rates[3].high;
      if(gapSize >= InpMinFVGSizePoints * point)
        {
         string msg = "🟢 BULLISH Silver Bullet (" + session + ")\n" + 
                      symbol + " on " + EnumToString(InpTimeframe) + "\n" +
                      "FVG Formed. Look for longs.";
         SendAlerts(msg);
         AddToHistory(symbol, rates[1].time);
        }
     }

   // --- BEARISH FVG LOGIC ---
   // Candle 3 Low > Candle 1 High (Gap exists)
   // Candle 2 is the displacement candle
   if(rates[3].low > rates[1].high)
     {
      double gapSize = rates[3].low - rates[1].high;
      if(gapSize >= InpMinFVGSizePoints * point)
        {
         string msg = "🔴 BEARISH Silver Bullet (" + session + ")\n" + 
                      symbol + " on " + EnumToString(InpTimeframe) + "\n" +
                      "FVG Formed. Look for shorts.";
         SendAlerts(msg);
         AddToHistory(symbol, rates[1].time);
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: Prevent duplicate alerts for the same candle             |
//+------------------------------------------------------------------+
bool IsAlreadyAlerted(string symbol, datetime time)
  {
   for(int i=0; i<ArraySize(alertHistory); i++)
     {
      if(alertHistory[i].symbol == symbol)
        {
         if(alertHistory[i].lastAlertBarTime == time) return true;
         return false;
        }
     }
   return false;
  }

void AddToHistory(string symbol, datetime time)
  {
   // Check if symbol exists in array, update it
   for(int i=0; i<ArraySize(alertHistory); i++)
     {
      if(alertHistory[i].symbol == symbol)
        {
         alertHistory[i].lastAlertBarTime = time;
         return;
        }
     }
   
   // If new symbol, resize array and add
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
