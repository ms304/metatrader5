//+------------------------------------------------------------------+
//|                            KijunScanner_Optimized_v4.2.mq5       |
//|                                  Copyright 2026, Didier Le HPI   |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI Réunionnais"
#property link      "https://www.Didier-Le-HPI-Réunionnais.re"
#property version   "4.20"
#property strict

//--- INPUTS
input group "Paramètres Ichimoku"
input ENUM_TIMEFRAMES InpScanTimeframe = PERIOD_CURRENT; // UT à scanner (PERIOD_CURRENT = UT du graphique)
input int      InpTenkan         = 9;      // Tenkan-sen
input int      InpKijun          = 26;     // Kijun-sen
input int      InpSenkou         = 52;     // Senkou Span B

input group "Paramètres du Scanner"
input string   InpManualSymbols  = "";     // Symboles (ex: EURUSD,GBPUSD) - Vide = Market Watch
input double   InpThresholdPercent = 0.10; // Seuil d'alerte en %
input int      InpScanSeconds    = 30;     // Fréquence du scan en secondes

input group "Notifications Mobile"
input bool     InpSendPush       = true;   // Envoyer notifications sur mobile
input int      InpAlertCooldown  = 60;     // Pause entre alertes sur même paire (minutes)

input group "Gestion de la Mémoire (RAM)"
input int      InpMemWarningMB   = 500;    // Alerte RAM (Mo) - Orange
input int      InpMemPauseMB     = 800;    // Pause Scan (Mo) - Rouge
input int      InpPauseSeconds   = 60;     // Durée de la pause si critique (sec)

input group "Interface Graphique"
input int      InpXOffset        = 20;     // Position X
input int      InpYOffset        = 20;     // Position Y
input int      InpFontSize       = 9;      // Taille police
input color    InpHeaderColor    = clrGold; 
input color    InpBgColor        = C'25,25,25'; 
input int      InpBgWidth        = 550;

//--- Structures
struct SymbolData
{
   string name;
   int    ichimokuHandle; 
   datetime lastAlertTenkan;
   datetime lastAlertKijun;
   datetime lastAlertSSB;
};

struct ScanResult 
{ 
   string sym; 
   double prc; 
   double diff; 
   string line; 
};

//--- Variables globales
string          g_symbols[];
SymbolData      g_symbolData[]; 
int             g_totalSymbols = 0;
string          g_prefix = "ScanIchi_";
ENUM_TIMEFRAMES g_currentTF;

// Variables d'état
datetime    g_pauseEndTime = 0;
bool        g_isPaused = false;
int         g_lastRowCount = 0; 

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_currentTF = (InpScanTimeframe == PERIOD_CURRENT) ? _Period : InpScanTimeframe;
   
   ObjectsDeleteAll(0, g_prefix);
   ReleaseHandles();
   InitSymbols();
   
   if(!InitHandles())
   {
      Print("Erreur critique : Impossible d'initialiser les handles.");
      return(INIT_FAILED);
   }
   
   CreateBackground(InpXOffset - 5, InpYOffset - 5, InpBgWidth, 100); 
   EventSetTimer(InpScanSeconds);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialisation                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, g_prefix);
   ReleaseHandles();
   ArrayFree(g_symbols);
   ArrayFree(g_symbolData);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Timer Loop                                                       |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_isPaused)
   {
      if(TimeCurrent() >= g_pauseEndTime) g_isPaused = false;
      else { UpdateMemoryStatusUI(); return; }
   }
   ScanMarket();
}

//+------------------------------------------------------------------+
//| Cœur du Scanner                                                  |
//+------------------------------------------------------------------+
void ScanMarket()
{
   CheckMemory();
   if(g_isPaused) return;

   long terminalRam = TerminalInfoInteger(TERMINAL_MEMORY_USED);
   long mqlRam = MQLInfoInteger(MQL_MEMORY_USED) / (1024 * 1024);

   ScanResult results[];
   ArrayResize(results, g_totalSymbols * 3); 
   
   int count = 0;
   string tfDisplay = StringSubstr(EnumToString(g_currentTF), 7); 
   datetime now = TimeCurrent();
   int cooldownSec = InpAlertCooldown * 60;

   for(int i = 0; i < g_totalSymbols; i++)
   {
      if(g_symbolData[i].ichimokuHandle == INVALID_HANDLE) continue;
      
      string symbol = g_symbolData[i].name;
      if(!SymbolInfoInteger(symbol, SYMBOL_SELECT)) continue; 

      double price = SymbolInfoDouble(symbol, SYMBOL_BID);
      if(price <= 0) continue; 

      // Récupération de TOUTES les lignes pour le filtrage
      double t = GetIchiValue(g_symbolData[i].ichimokuHandle, 0); // Tenkan
      double k = GetIchiValue(g_symbolData[i].ichimokuHandle, 1); // Kijun
      double a = GetIchiValue(g_symbolData[i].ichimokuHandle, 2); // SSA
      double b = GetIchiValue(g_symbolData[i].ichimokuHandle, 3); // SSB

      // --- TEST TENKAN ---
      CheckLogic(i, t, t, k, a, b, "Tenkan", price, now, cooldownSec, results, count);
      // --- TEST KIJUN ---
      CheckLogic(i, k, t, k, a, b, "Kijun", price, now, cooldownSec, results, count);
      // --- TEST SSB ---
      CheckLogic(i, b, t, k, a, b, "SSB", price, now, cooldownSec, results, count);
   }
   
   ArrayResize(results, count);
   UpdateDashboard(results, count, terminalRam, mqlRam, tfDisplay);
   ArrayFree(results); 
}

//+------------------------------------------------------------------+
//| Logique de vérification (Alignement de toutes les lignes)        |
//+------------------------------------------------------------------+
void CheckLogic(int symIdx, double lineVal, double t, double k, double a, double b, 
                string lineName, double price, datetime now, int cooldown, ScanResult &res[], int &count)
{
   if(lineVal <= 0 || t <= 0 || k <= 0 || a <= 0 || b <= 0) return;

   double dev = ((price - lineVal) / price) * 100.0;
   
   // 1. Vérifier si on est dans le seuil de proximité
   if(MathAbs(dev) <= InpThresholdPercent)
   {
      bool isAligned = false;

      // 2. Vérification de l'alignement (Toutes les lignes doivent être du même côté que la ligne scannée)
      if(price > lineVal) // L'actif est AU-DESSUS (Support potentiel)
      {
         // Toutes les lignes doivent être sous le prix
         if(price > t && price > k && price > a && price > b) isAligned = true;
      }
      else // L'actif est EN-DESSOUS (Résistance potentielle)
      {
         // Toutes les lignes doivent être au-dessus du prix
         if(price < t && price < k && price < a && price < b) isAligned = true;
      }

      if(isAligned)
      {
         res[count].sym = g_symbolData[symIdx].name;
         res[count].prc = price;
         res[count].diff = dev;
         res[count].line = lineName;
         
         // Gestion Alertes
         datetime lastA = 0;
         if(lineName=="Tenkan") lastA = g_symbolData[symIdx].lastAlertTenkan;
         else if(lineName=="Kijun") lastA = g_symbolData[symIdx].lastAlertKijun;
         else lastA = g_symbolData[symIdx].lastAlertSSB;

         if(now - lastA > cooldown)
         {
            SendAlert(g_symbolData[symIdx].name, lineName, price, dev, g_currentTF);
            if(lineName=="Tenkan") g_symbolData[symIdx].lastAlertTenkan = now;
            else if(lineName=="Kijun") g_symbolData[symIdx].lastAlertKijun = now;
            else g_symbolData[symIdx].lastAlertSSB = now;
         }
         count++;
      }
   }
}

//+------------------------------------------------------------------+
//| Fonctions Utilitaires et Mémoire                                 |
//+------------------------------------------------------------------+
void CheckMemory()
{
   long memUsedMB = TerminalInfoInteger(TERMINAL_MEMORY_USED); 
   if(memUsedMB >= InpMemPauseMB)
   {
      if(!g_isPaused)
      {
         g_isPaused = true;
         g_pauseEndTime = TimeCurrent() + InpPauseSeconds;
         UpdateMemoryStatusUI(); 
      }
   }
}

void InitSymbols()
{
   ArrayFree(g_symbols); 
   if(InpManualSymbols != "")
   {
      ushort sep = StringGetCharacter(",", 0);
      StringSplit(InpManualSymbols, sep, g_symbols);
   }
   else
   {
      int total = SymbolsTotal(true); 
      ArrayResize(g_symbols, total);
      for(int i=0; i<total; i++) g_symbols[i] = SymbolName(i, true);
   }
   g_totalSymbols = ArraySize(g_symbols);
}

bool InitHandles()
{
   ArrayFree(g_symbolData);
   if(ArrayResize(g_symbolData, g_totalSymbols) <= 0) return false;
   
   for(int i = 0; i < g_totalSymbols; i++)
   {
      g_symbolData[i].name = g_symbols[i];
      g_symbolData[i].ichimokuHandle = iIchimoku(g_symbolData[i].name, g_currentTF, InpTenkan, InpKijun, InpSenkou);
      g_symbolData[i].lastAlertTenkan = 0;
      g_symbolData[i].lastAlertKijun = 0;
      g_symbolData[i].lastAlertSSB = 0;
   }
   return(true);
}

void ReleaseHandles()
{
   for(int i = 0; i < ArraySize(g_symbolData); i++)
   {
      if(g_symbolData[i].ichimokuHandle != INVALID_HANDLE)
      {
         IndicatorRelease(g_symbolData[i].ichimokuHandle);
         g_symbolData[i].ichimokuHandle = INVALID_HANDLE;
      }
   }
}

double GetIchiValue(int handle, int bufferIdx)
{
   if(handle == INVALID_HANDLE) return 0.0;
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if(CopyBuffer(handle, bufferIdx, 0, 1, buffer) <= 0) return 0.0;
   return buffer[0];
}

//+------------------------------------------------------------------+
//| Interface Graphique                                              |
//+------------------------------------------------------------------+
void UpdateDashboard(ScanResult &data[], int count, long totalRam, long scriptRam, string tf)
{
   UpdateLabel(g_prefix+"h1", StringFormat("ICHIMOKU [%s] - Filtre Alignement Actif", tf), InpXOffset, InpYOffset, InpHeaderColor);
   string ramTxt = StringFormat("Term RAM: %d MB | Script: %d MB", totalRam, scriptRam);
   UpdateLabel(g_prefix+"ram", ramTxt, InpXOffset, InpYOffset + 15, (totalRam>InpMemWarningMB)?clrOrange:clrLime);
   UpdateLabel(g_prefix+"cols", "Symbole  | Prix     | Ligne  | Dist %", InpXOffset, InpYOffset + 30, clrWhite);
   
   int startY = InpYOffset + 50;
   int lineHeight = InpFontSize + 6;
   
   if(count == 0)
   {
      UpdateLabel(g_prefix+"row_0", "Aucun actif aligné détecté...", InpXOffset, startY, clrGray);
      count = 1; 
   }
   else
   {
      for(int i = 0; i < count; i++)
      {
         color txtColor = (data[i].diff >= 0) ? clrLime : clrRed;
         string lineStr = StringFormat("%-8s | %-8.5f | %-6s | %+.2f%%", 
                                    data[i].sym, data[i].prc, data[i].line, data[i].diff);
         UpdateLabel(g_prefix+"row_"+(string)i, lineStr, InpXOffset, startY + (i*lineHeight), txtColor);
      }
   }
   
   if(g_lastRowCount > count)
   {
      for(int k = count; k < g_lastRowCount; k++) ObjectDelete(0, g_prefix+"row_"+(string)k);
   }
   g_lastRowCount = count;
   
   int bgH = 65 + (count * lineHeight);
   ObjectSetInteger(0, g_prefix+"bg", OBJPROP_YSIZE, bgH);
   ChartRedraw();
}

void UpdateMemoryStatusUI()
{
   UpdateLabel(g_prefix+"h1", "!!! PAUSE RAM !!! Nettoyage...", InpXOffset, InpYOffset, clrRed);
   ChartRedraw();
}

void UpdateLabel(string name, string text, int x, int y, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas"); 
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
}

void CreateBackground(int x, int y, int w, int h)
{
   string name = g_prefix + "bg";
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, InpBgColor);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
}

void SendAlert(string symbol, string line, double price, double diff, ENUM_TIMEFRAMES tf)
{
   if(!InpSendPush) return;
   string msg = StringFormat("ALIGNEMENT ICHIMOKU %s: %s sur %s (%.2f%%)", 
                             StringSubstr(EnumToString(tf), 7), line, symbol, diff);
   SendNotification(msg);
}
