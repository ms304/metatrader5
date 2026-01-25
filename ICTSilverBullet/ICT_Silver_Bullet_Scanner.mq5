//+------------------------------------------------------------------+
//|                                     ICT_Silver_Bullet_Scanner.mq5 |
//|                                     Copyright 2023, Silver Bullet Logic   |
//|                                             Based on ICT Concepts         |
//+------------------------------------------------------------------+
#property copyright "mc0d3 t0w3rbu5t3r"
#property link      ""
#property version   "1.00"
#property strict

//--- INPUTS ---
input group "Time Settings"
input int      InpBrokerHourFor10AM = 17;    // Broker Hour when it is 10:00 AM New York (Crucial!)
input ENUM_TIMEFRAMES InpTimeframe  = PERIOD_M5; // Timeframe to Scan (M1, M5 recommended)

input group "Setup Configuration"
input double   InpMinFVGSizePoints  = 1.0;   // Minimum Gap Size (Points) to trigger alert

input group "Alerts"
input bool     InpAlertPopUp        = true;  // Alert: Pop-up Window
input bool     InpAlertPush         = true;  // Alert: Mobile Push Notification
input bool     InpAlertSound        = true;  // Alert: Sound

//--- GLOBAL VARIABLES ---
int NY_3AM_Hour;
int NY_10AM_Hour;
int NY_2PM_Hour;

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
   // --- CALCULATE TIME WINDOWS ---
   // 10 AM NY is the reference point.
   // 3 AM NY is 7 hours before 10 AM.
   // 2 PM (14:00) NY is 4 hours after 10 AM.
   
   NY_10AM_Hour = InpBrokerHourFor10AM;
   NY_3AM_Hour  = InpBrokerHourFor10AM - 7;
   NY_2PM_Hour  = InpBrokerHourFor10AM + 4;
   
   // Adjust for day rollover (e.g., if calculation results in negative hour)
   if(NY_3AM_Hour < 0) NY_3AM_Hour += 24;
   if(NY_3AM_Hour >= 24) NY_3AM_Hour -= 24;
   
   if(NY_2PM_Hour < 0) NY_2PM_Hour += 24;
   if(NY_2PM_Hour >= 24) NY_2PM_Hour -= 24;
   
   if(NY_10AM_Hour >= 24) NY_10AM_Hour -= 24;

   Print("--- ICT SILVER BULLET REAL-TIME SCANNER STARTED ---");
   Print("Scanning timeframe: ", EnumToString(InpTimeframe));
   Print("London Open SB (3AM NY) starts at Broker Hour: ", NY_3AM_Hour);
   Print("AM Session SB (10AM NY) starts at Broker Hour: ", NY_10AM_Hour);
   Print("PM Session SB (2PM NY) starts at Broker Hour: ", NY_2PM_Hour);
   
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
   // 1. Get Current Broker Time
   datetime currentTime = TimeCurrent();
   MqlDateTime tm;
   TimeToStruct(currentTime, tm);
   
   // 2. Check if we are in a Silver Bullet Window
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
   
   // If not in time window, stop scanning to save resources
   if(!isSilverBullet) return; 

   // 3. Loop through Market Watch Symbols
   int total = SymbolsTotal(true); // true = only visible in Market Watch
   
   for(int i = 0; i < total; i++)
     {
      string symbol = SymbolName(i, true);
      ScanSymbolForRealTimeFVG(symbol, sessionName);
     }
  }

//+------------------------------------------------------------------+
//| Logic to Detect FVG (REAL-TIME / DURING FORMATION)               |
//+------------------------------------------------------------------+
void ScanSymbolForRealTimeFVG(string symbol, string session)
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
         string msg = "🟢 BULLISH Silver Bullet (" + session + ")\n" + 
                      symbol + " (" + EnumToString(InpTimeframe) + ")\n" +
                      "Setup forming NOW (Real-Time).";
         
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
         string msg = "🔴 BEARISH Silver Bullet (" + session + ")\n" + 
                      symbol + " (" + EnumToString(InpTimeframe) + ")\n" +
                      "Setup forming NOW (Real-Time).";
         
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
