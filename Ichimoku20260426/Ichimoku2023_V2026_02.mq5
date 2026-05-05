//+------------------------------------------------------------------+
//|                                          Ichimoku2023_Scanner.mq5 |
//|                          Copyright 2023, Invest Data Systems FR. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
// Version avec détection de transition d'état (non validé -> validé)
// Signal : Haussier complet (strict)
// Scan   : À chaque nouveau tick
// Alertes : printf / Alert / SendNotification

#property copyright "Copyright 2023, Invest Data Systems France."
#property link      "https://www.mql5.com"
#property version   "1.01"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Paramètres d'entrée                                              |
//+------------------------------------------------------------------+
input bool enableTrading    = true;
input int  tenkan_period    = 9;
input int  kijun_period     = 26;
input int  senkou_b_period  = 52;

//+------------------------------------------------------------------+
//| Variables globales                                               |
//+------------------------------------------------------------------+
CTrade trade;

// Mémorisation des états précédents par symbole
string  g_symbols[];       // noms des symboles du MarketWatch
bool    g_prevState[];     // état validé (true/false) au tick précédent
int     g_symbolCount = 0;

//+------------------------------------------------------------------+
//| Buffers Ichimoku (réutilisés à chaque appel)                     |
//+------------------------------------------------------------------+
double tenkan_sen_buffer[];
double kijun_sen_buffer[];
double senkou_span_a_buffer[];
double senkou_span_b_buffer[];
double chikou_span_buffer[];
MqlRates mql_rates[];

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   ArraySetAsSeries(mql_rates,            true);
   ArraySetAsSeries(tenkan_sen_buffer,    true);
   ArraySetAsSeries(kijun_sen_buffer,     true);
   ArraySetAsSeries(senkou_span_a_buffer, true);
   ArraySetAsSeries(senkou_span_b_buffer, true);
   ArraySetAsSeries(chikou_span_buffer,   true);

   // Construire la liste des symboles du MarketWatch
   bool onlyMarketWatch = true;
   g_symbolCount = SymbolsTotal(onlyMarketWatch);

   ArrayResize(g_symbols,   g_symbolCount);
   ArrayResize(g_prevState, g_symbolCount);

   // Première passe : enregistrer l'état réel de chaque symbole sans alerter
   string alreadyValid = "";
   int    alreadyCount = 0;

   for(int i = 0; i < g_symbolCount; i++)
     {
      g_symbols[i]   = SymbolName(i, onlyMarketWatch);
      g_prevState[i] = IchimokuBullishStrict(g_symbols[i]); // état réel au démarrage

      if(g_prevState[i])
        {
         alreadyCount++;
         alreadyValid += g_symbols[i] + " ";
        }
     }

   printf("[Ichimoku Scanner] Initialisé sur " + string(g_symbolCount) + " symboles.");
   printf("[Ichimoku Scanner] Déjà validés au démarrage (" + string(alreadyCount) + ") : " + alreadyValid);
   printf("[Ichimoku Scanner] En attente de nouvelles transitions...");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Déinitialisation                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ArrayFree(g_symbols);
   ArrayFree(g_prevState);
  }

//+------------------------------------------------------------------+
//| OnTick : scan à chaque nouveau tick                              |
//+------------------------------------------------------------------+
void OnTick()
  {
   for(int i = 0; i < g_symbolCount; i++)
     {
      string sname    = g_symbols[i];
      bool   curState = IchimokuBullishStrict(sname);

      // Détection de transition false -> true uniquement
      if(curState == true && g_prevState[i] == false)
        {
         string msg = "[Ichimoku Scanner] SIGNAL HAUSSIER STRICT : " + sname
                      + " | " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

         // 1. Journal
         printf(msg);

         // 2. Alerte visuelle
         Alert(msg);

         // 3. Notification push mobile
         SendNotification(msg);
        }

      // Mémoriser l'état courant pour le prochain tick
      g_prevState[i] = curState;
     }
  }

//+------------------------------------------------------------------+
//| Calcule et retourne true si le signal haussier strict est validé |
//| pour le symbole donné                                            |
//+------------------------------------------------------------------+
bool IchimokuBullishStrict(string sname)
  {
   int max    = 64;
   int handle = iIchimoku(sname, PERIOD_CURRENT, tenkan_period, kijun_period, senkou_b_period);

   if(handle == INVALID_HANDLE)
      return false;

   // Copie des buffers
   int nbt   = CopyBuffer(handle, TENKANSEN_LINE,   0, max, tenkan_sen_buffer);
   int nbk   = CopyBuffer(handle, KIJUNSEN_LINE,    0, max, kijun_sen_buffer);
   int nbssa = CopyBuffer(handle, SENKOUSPANA_LINE, 0, max, senkou_span_a_buffer);
   int nbssb = CopyBuffer(handle, SENKOUSPANB_LINE, 0, max, senkou_span_b_buffer);
   int nbc   = CopyBuffer(handle, CHIKOUSPAN_LINE,  0, max, chikou_span_buffer);

   // Vérifier que les copies ont réussi
   if(nbt <= 0 || nbk <= 0 || nbssa <= 0 || nbssb <= 0 || nbc <= 0)
     {
      IndicatorRelease(handle);
      return false;
     }

   // Copie des rates
   if(CopyRates(sname, PERIOD_CURRENT, 0, 32, mql_rates) <= 0)
     {
      IndicatorRelease(handle);
      return false;
     }

   // --- Valeurs courantes (bougie [0]) ---
   double close0  = mql_rates[0].close;
   double ssa0    = senkou_span_a_buffer[0];
   double ssb0    = senkou_span_b_buffer[0];
   double tenkan0 = tenkan_sen_buffer[0];
   double kijun0  = kijun_sen_buffer[0];

   // --- Valeurs du Chikou Span (décalé 26 bougies en arrière) ---
   double cs        = chikou_span_buffer[26];
   double ssb_cs    = senkou_span_b_buffer[26];
   double ssa_cs    = senkou_span_a_buffer[27]; // SSA décalé d'une bougie supplémentaire
   double tenkan_cs = tenkan_sen_buffer[27];
   double kijun_cs  = kijun_sen_buffer[26];

   // Libération du handle
   IndicatorRelease(handle);

   // Libération des buffers
   ArrayFree(senkou_span_b_buffer);
   ArrayFree(senkou_span_a_buffer);
   ArrayFree(tenkan_sen_buffer);
   ArrayFree(kijun_sen_buffer);
   ArrayFree(chikou_span_buffer);
   ArrayFree(mql_rates);

   // Réinitialisation comme séries pour le prochain appel
   ArraySetAsSeries(mql_rates,            true);
   ArraySetAsSeries(tenkan_sen_buffer,    true);
   ArraySetAsSeries(kijun_sen_buffer,     true);
   ArraySetAsSeries(senkou_span_a_buffer, true);
   ArraySetAsSeries(senkou_span_b_buffer, true);
   ArraySetAsSeries(chikou_span_buffer,   true);

   // --- Condition haussier strict (identique à l'original) ---
   bool priceAboveCloud  = (close0 > ssb0 && close0 > ssa0);
   bool priceAboveLines  = (close0 > tenkan0 && close0 > kijun0);
   bool chikouValidated  = (cs > tenkan_cs && cs > kijun_cs && cs > ssa_cs && cs > ssb_cs);

   return (priceAboveCloud && priceAboveLines && chikouValidated);
  }

//+------------------------------------------------------------------+
//| Retourne true uniquement sur la première bougie d'un nouveau bar |
//+------------------------------------------------------------------+
bool isNewBar()
  {
   static datetime last_time = 0;
   datetime lastbar_time = SeriesInfoInteger(Symbol(), Period(), SERIES_LASTBAR_DATE);

   if(last_time == 0)
     {
      last_time = lastbar_time;
      return false;
     }

   if(last_time != lastbar_time)
     {
      last_time = lastbar_time;
      return true;
     }

   return false;
  }
//+------------------------------------------------------------------+
