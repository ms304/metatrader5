//+------------------------------------------------------------------+
//|                                     Ichimoku_Kijun_Breakout_V2.mq5|
//|                                  Copyright 2026, Didier Le HPI   | Efficace sur BTCUSD H4 du 01/01/2025 au 15/02/2026
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//--- INPUTS
input group "Paramètres Ichimoku"
input int InpTenkan = 9;
input int InpKijun  = 26;
input int InpSenkou = 52;

input group "Gestion du Risque"
input double InpLotSize = 0.1;
input double InpRewardRatio = 2.0; // Ratio 1:2
input int    InpMagic = 123456;

//--- VARIABLES GLOBALES
int      handleIchimoku;
CTrade   trade;

// Variables pour l'Achat (Long)
double   lastDetectedHigh = 0;
bool     isWaitingForLong = false;
bool     longPullbackConfirmed = false;

// Variables pour la Vente (Short)
double   lastDetectedLow = 0;
bool     isWaitingForShort = false;
bool     shortPullbackConfirmed = false;

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   handleIchimoku = iIchimoku(_Symbol, _Period, InpTenkan, InpKijun, InpSenkou);
   if(handleIchimoku == INVALID_HANDLE) return(INIT_FAILED);
   
   trade.SetExpertMagicNumber(InpMagic);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialisation                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleIchimoku);
}

//+------------------------------------------------------------------+
//| OnTick - Logique principale                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!isNewBar()) return;

   double kijun[];
   double close[];
   ArraySetAsSeries(kijun, true);
   ArraySetAsSeries(close, true);
   
   if(CopyBuffer(handleIchimoku, 1, 0, 3, kijun) < 3) return;
   if(CopyClose(_Symbol, _Period, 0, 3, close) < 3) return;

   //--- LOGIQUE DE DÉTECTION DES SIGNAUX ---

   // 1. Signal d'Achat : Passage au-dessus de la Kijun
   if(close[1] > kijun[1] && close[2] <= kijun[2])
   {
      lastDetectedHigh = close[1];
      isWaitingForLong = true;
      longPullbackConfirmed = false;
      // On annule un potentiel signal de vente
      isWaitingForShort = false;
      Print("Signal LONG détecté : On surveille le plus haut.");
   }

   // 2. Signal de Vente : Passage en-dessous de la Kijun
   if(close[1] < kijun[1] && close[2] >= kijun[2])
   {
      lastDetectedLow = close[1];
      isWaitingForShort = true;
      shortPullbackConfirmed = false;
      // On annule un potentiel signal d'achat
      isWaitingForLong = false;
      Print("Signal SHORT détecté : On surveille le plus bas.");
   }

   //--- LOGIQUE DE SURVEILLANCE ET ENTRÉE ---

   // Gestion du LONG
   if(isWaitingForLong)
   {
      if(close[1] < kijun[1]) { isWaitingForLong = false; lastDetectedHigh = 0; } // Annulation
      else 
      {
         if(!longPullbackConfirmed)
         {
            if(close[1] > lastDetectedHigh) lastDetectedHigh = close[1];
            if(close[1] < close[2]) longPullbackConfirmed = true; 
         }
         
         if(longPullbackConfirmed && close[0] > lastDetectedHigh)
         {
            if(PositionsTotal() == 0) ExecuteTrade(ORDER_TYPE_BUY, kijun[0]);
            isWaitingForLong = false;
         }
      }
   }

   // Gestion du SHORT
   if(isWaitingForShort)
   {
      if(close[1] > kijun[1]) { isWaitingForShort = false; lastDetectedLow = 0; } // Annulation
      else 
      {
         if(!shortPullbackConfirmed)
         {
            if(close[1] < lastDetectedLow) lastDetectedLow = close[1];
            if(close[1] > close[2]) shortPullbackConfirmed = true; 
         }
         
         if(shortPullbackConfirmed && close[0] < lastDetectedLow)
         {
            if(PositionsTotal() == 0) ExecuteTrade(ORDER_TYPE_SELL, kijun[0]);
            isWaitingForShort = false;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Exécution des ordres                                             |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double slLevel)
{
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = slLevel;
   double risk = MathAbs(price - sl);
   double tp = (type == ORDER_TYPE_BUY) ? (price + risk * InpRewardRatio) : (price - risk * InpRewardRatio);
   
   if(type == ORDER_TYPE_BUY)
      trade.Buy(InpLotSize, _Symbol, price, sl, tp, "Kijun Breakout Long");
   else
      trade.Sell(InpLotSize, _Symbol, price, sl, tp, "Kijun Breakout Short");
}

//+------------------------------------------------------------------+
//| Fonction barres                                                  |
//+------------------------------------------------------------------+
bool isNewBar()
{
   static datetime lastBar;
   datetime currentBar = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(lastBar != currentBar) { lastBar = currentBar; return true; }
   return false;
}
