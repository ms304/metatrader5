//+------------------------------------------------------------------+
//|                                           Ichimoku2023_v2026.mq5 |
//|                     Copyright 2023-2026, Invest Data Systems FR. |
//|                           https://bitcointrader2022.blogspot.com |
//+------------------------------------------------------------------+

// Version that contains detailed infos in backtesting journal.

#property copyright "Copyright 2023, Invest Data Systems France."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

double bid, ask;

input bool enableTrading = true;

CTrade trade;
MqlRates mql_rates[];
double tenkan_sen_buffer[];
double kijun_sen_buffer[];
double senkou_span_a_buffer[];
double senkou_span_b_buffer[];
double chikou_span_buffer[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   printf(TerminalInfoString(TERMINAL_PATH));
   ArraySetAsSeries(mql_rates, true);
   ArraySetAsSeries(tenkan_sen_buffer,true);
   ArraySetAsSeries(kijun_sen_buffer,true);
   ArraySetAsSeries(senkou_span_a_buffer,true);
   ArraySetAsSeries(senkou_span_b_buffer,true);
   ArraySetAsSeries(chikou_span_buffer,true);


   printf("DEBUT DES TRAITEMENTS");

   bool onlySymbolsInMarketwatch = true;

   int stotal=SymbolsTotal(onlySymbolsInMarketwatch); // seulement les symboles dans le marketwatch (false)
   for(int sindex=0; sindex<stotal; sindex++)
     {
      string sname=SymbolName(sindex, onlySymbolsInMarketwatch);
      //printf("Current symbol = " + sname);
      Ichimoku(sname);
     }

   printf("FIN DES TRAITEMENTS");


   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer()
  {
  }


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+

datetime dtRef;

bool done = false;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
  }
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Ichimoku(string sname)
  {
//if(isNewBar() == false)
//   return;

   if(CopyRates(sname, PERIOD_CURRENT, 0, 32, mql_rates)>0)
     {
     }
   else
     {
      //Print("CopyRates(" + sname + ", PERIOD_CURRENT,1, 10, mql_rates). Error ", GetLastError());
     }


   bid = SymbolInfoDouble(sname, SYMBOL_BID);
   ask = SymbolInfoDouble(sname, SYMBOL_ASK);

   int tenkan_sen = 9;              // period of Tenkan-sen
   int kijun_sen = 26;              // period of Kijun-sen
   int senkou_span_b = 52;          // period of Senkou Span B

   int max = 64;
   int handle;
   handle = iIchimoku(sname, PERIOD_CURRENT, tenkan_sen, kijun_sen, senkou_span_b);
   if(handle != INVALID_HANDLE)
     {
      int nbt = -1, nbk = -1, nbssa = -1, nbssb = -1, nbc = -1;
      nbt = CopyBuffer(handle, TENKANSEN_LINE, 0, max, tenkan_sen_buffer);
      nbk = CopyBuffer(handle, KIJUNSEN_LINE, 0, max, kijun_sen_buffer);
      nbssa = CopyBuffer(handle, SENKOUSPANA_LINE, 0, max, senkou_span_a_buffer);
      nbssb = CopyBuffer(handle, SENKOUSPANB_LINE, 0, max, senkou_span_b_buffer);
      nbc = CopyBuffer(handle, CHIKOUSPAN_LINE, 0, max, chikou_span_buffer);

      double cs = chikou_span_buffer[26];
      double ssb_cs = senkou_span_b_buffer[26];
      double ssa_cs = senkou_span_a_buffer[27];
      double tenkan_cs = tenkan_sen_buffer[27];
      double kijun_cs = kijun_sen_buffer[26];

      if(nbk > 0)
        {
         if(mql_rates[0].close > senkou_span_b_buffer[0]
            && mql_rates[0].close > senkou_span_a_buffer[0]
            && mql_rates[0].close > tenkan_sen_buffer[0]
            && mql_rates[0].close > kijun_sen_buffer[0]
            && cs > tenkan_cs
            && cs > kijun_cs
            && cs > ssa_cs
            && cs > ssb_cs
           )
           {
            printf(sname + " is validated");
           }

         if(/*(mql_rates[0].close > Highest26) &&*/
            ((mql_rates[2].close > senkou_span_b_buffer[2] && mql_rates[2].close > senkou_span_a_buffer[2]))
            &&(mql_rates[1].close > senkou_span_b_buffer[1] && mql_rates[1].close > senkou_span_a_buffer[1]))
           {
            /*printf("Is above the cloud SSB and SSA");
            printf("chikou span =" + string(chikou_span_buffer[26]) + " at " + string(mql_rates[27].time));
            printf("senkou span b cs=" + string(senkou_span_b_buffer[26]));
            printf("senkou span a cs=" + string(senkou_span_a_buffer[27]));
            printf("tenkan cs=" + string(tenkan_sen_buffer[27]));
            printf("kijun cs=" + string(kijun_sen_buffer[26]));*/

            if(cs > ssb_cs && cs > ssa_cs && cs > tenkan_cs && cs > kijun_cs)
              {
               /*printf("chikou span est validée sur la bougie de " + string(mql_rates[27].time));
               printf("ssb bougie précédente de [" + string(mql_rates[1].time) + "] = " + string(senkou_span_b_buffer[1]));
               printf("ssa bougie précédente de [" + string(mql_rates[1].time) + "] = " + string(senkou_span_a_buffer[1]));
               printf("tenkan bougie précédente de [" + string(mql_rates[1].time) + "] = " + string(tenkan_sen_buffer[1]));
               printf("kijun bougie précédente de [" + string(mql_rates[1].time) + "] = " + string(kijun_sen_buffer[1]));*/

               double close = mql_rates[1].close;
               double ssa = senkou_span_a_buffer[1];
               double ssb = senkou_span_b_buffer[1];
               double tenkan = tenkan_sen_buffer[1];
               double kijun = kijun_sen_buffer[1];

               /*// Calcul de la distance avec la tenkan sen
               double diff = mql_rates[0].close - tenkan_sen_buffer[0];
               printf("Diff Close0-Tenkan0 = " + string(diff));
               double diffpercent = (mql_rates[0].close - tenkan_sen_buffer[0])/tenkan_sen_buffer[0] * 100;
               printf("Diff in % = " + string(diffpercent));*/

               //if(diffpercent > 0 && diffpercent < 0.02)
               //{

               if(close > ssa && close > ssb /*&& close > tenkan*/ && close > kijun)
                 {
                  //printf("le prix est validé sur la bougie de " + string(mql_rates[1].time));

                 }

               //}

              }
           }

         // Nouveau condition ajoutée dans IchimokuEA005
         if(/*(mql_rates[0].close < Lowest26) &&*/
            ((mql_rates[2].close < senkou_span_b_buffer[2] && mql_rates[2].close < senkou_span_a_buffer[2]))
            &&(mql_rates[1].close < senkou_span_b_buffer[1] && mql_rates[1].close < senkou_span_a_buffer[1]))
           {
            /*printf("Is below the cloud SSB and SSA");
            printf("chikou span =" + string(chikou_span_buffer[26]) + " at " + string(mql_rates[27].time));
            printf("senkou span b cs=" + string(senkou_span_b_buffer[26]));
            printf("senkou span a cs=" + string(senkou_span_a_buffer[27]));
            printf("tenkan cs=" + string(tenkan_sen_buffer[27]));
            printf("kijun cs=" + string(kijun_sen_buffer[26]));*/

            /*double cs = chikou_span_buffer[26];
            double ssb_cs = senkou_span_b_buffer[26];
            double ssa_cs = senkou_span_a_buffer[27];
            double tenkan_cs = tenkan_sen_buffer[27];
            double kijun_cs = kijun_sen_buffer[26];*/

            if(cs < ssb_cs && cs < ssa_cs && cs < tenkan_cs && cs < kijun_cs)
              {
               /*printf("chikou span est validée sur la bougie de " + string(mql_rates[27].time));
               printf("ssb bougie précédente de [" + string(mql_rates[1].time) + "] = " + string(senkou_span_b_buffer[1]));
               printf("ssa bougie précédente de [" + string(mql_rates[1].time) + "] = " + string(senkou_span_a_buffer[1]));
               printf("tenkan bougie précédente de [" + string(mql_rates[1].time) + "] = " + string(tenkan_sen_buffer[1]));
               printf("kijun bougie précédente de [" + string(mql_rates[1].time) + "] = " + string(kijun_sen_buffer[1]));*/

               double close = mql_rates[1].close;
               double ssa = senkou_span_a_buffer[1];
               double ssb = senkou_span_b_buffer[1];
               double tenkan = tenkan_sen_buffer[1];
               double kijun = kijun_sen_buffer[1];

               /*// Calcul de la distance avec la tenkan sen
               double diff = mql_rates[0].close - tenkan_sen_buffer[0];
               printf("Diff Close0-Tenkan0 = " + string(diff));
               double diffpercent = (mql_rates[0].close - tenkan_sen_buffer[0])/tenkan_sen_buffer[0] * 100;
               printf("Diff in % = " + string(diffpercent));*/

               //if(diffpercent < 0 && diffpercent > -0.02)
               //{
               if(close < ssa && close < ssb && close < tenkan && close < kijun)
                 {
                  //printf("le prix est validé sur la bougie de " + string(mql_rates[1].time));

                 }
               //}

              }
           }



        }

      ArrayFree(senkou_span_b_buffer);
      ArrayFree(senkou_span_a_buffer);
      ArrayFree(tenkan_sen_buffer);
      ArrayFree(kijun_sen_buffer);
      ArrayFree(chikou_span_buffer);
      ArrayFree(mql_rates);


     }
  }



//+------------------------------------------------------------------+
//| Returns true if a new bar has appeared for a symbol/period pair  |
//+------------------------------------------------------------------+
bool isNewBar()
  {
//printf("isnewbar function");
//--- memorize the time of opening of the last bar in the static variable
   static datetime last_time=0;
//--- current time
   datetime lastbar_time=SeriesInfoInteger(Symbol(),Period(),SERIES_LASTBAR_DATE);

//printf(string(last_time));

//printf(string(last_time));

//--- if it is the first call of the function
   if(last_time==0)
     {
      //--- set the time and exit
      last_time=lastbar_time;
      return(false);
     }

//--- if the time differs
   if(last_time!=lastbar_time)
     {
      //printf("is a new bar");
      //--- memorize the time and return true
      last_time=lastbar_time;
      return(true);
     }
//--- if we passed to this line, then the bar is not new; return false
   return(false);
  }

//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
