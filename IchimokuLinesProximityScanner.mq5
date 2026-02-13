//+------------------------------------------------------------------+
//|                            KijunScanner_Optimized_v4.1.mq5       |
//|                                  Copyright 2026, Didier Le HPI   |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI Réunionnais"
#property link      "https://www.Didier-Le-HPI-Réunionnais.re"
#property version   "4.10"
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
   // 1. Détecter l'UT (si PERIOD_CURRENT, on prend celle du graphique actuel)
   g_currentTF = (InpScanTimeframe == PERIOD_CURRENT) ? _Period : InpScanTimeframe;
   
   // 2. Nettoyer tout ce qui pourrait exister en mémoire
   ObjectsDeleteAll(0, g_prefix);
   ReleaseHandles();
   
   // 3. Initialiser les listes
   InitSymbols();
   
   // 4. Créer les handles d'indicateurs
   if(!InitHandles())
   {
      Print("Erreur critique : Impossible d'initialiser les handles.");
      return(INIT_FAILED);
   }
   
   CreateBackground(InpXOffset - 5, InpYOffset - 5, InpBgWidth, 100); 
   EventSetTimer(InpScanSeconds);
   
   Print("Scanner Initialisé sur l'UT: ", EnumToString(g_currentTF));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialisation                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, g_prefix);
   
   ReleaseHandles(); // Libération des handles d'indicateurs
   
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
      if(TimeCurrent() >= g_pauseEndTime)
      {
         g_isPaused = false;
         Print("RAM stabilisée. Reprise du scan.");
      }
      else
      {
         UpdateMemoryStatusUI(); 
         return;
      }
   }
   
   ScanMarket();
}

//+------------------------------------------------------------------+
//| Logique Mémoire                                                  |
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
         Print("ALERTE RAM: ", memUsedMB, " Mo. Pause.");
         UpdateMemoryStatusUI(); 
      }
   }
}

//+------------------------------------------------------------------+
//| Initialisation des symboles                                      |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Gestion des Handles                                              |
//+------------------------------------------------------------------+
bool InitHandles()
{
   ArrayFree(g_symbolData);
   if(ArrayResize(g_symbolData, g_totalSymbols) <= 0) return false;
   
   for(int i = 0; i < g_totalSymbols; i++)
   {
      g_symbolData[i].name = g_symbols[i];
      // Utilisation de l'UT détectée dynamiquement
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

//+------------------------------------------------------------------+
//| Cœur du Scanner                                                  |
//+------------------------------------------------------------------+
void ScanMarket()
{
   CheckMemory();
   if(g_isPaused) return;

   long terminalRam = TerminalInfoInteger(TERMINAL_MEMORY_USED);
   long mqlRam = MQLInfoInteger(MQL_MEMORY_USED) / (1024 * 1024);

   // Remplacement de ArrayReserve par une allocation directe
   ScanResult results[];
   ArrayResize(results, g_totalSymbols * 3); // Taille max possible
   
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

      // --- TEST TENKAN (Buffer 0) ---
      CheckAndAddResult(i, 0, "Tenkan", price, now, cooldownSec, results, count);
      // --- TEST KIJUN (Buffer 1) ---
      CheckAndAddResult(i, 1, "Kijun",  price, now, cooldownSec, results, count);
      // --- TEST SSB (Buffer 3) ---
      CheckAndAddResult(i, 3, "SSB",    price, now, cooldownSec, results, count);
   }
   
   // On ajuste la taille du tableau au nombre réel de trouvailles
   ArrayResize(results, count);
   UpdateDashboard(results, count, terminalRam, mqlRam, tfDisplay);
   ArrayFree(results); 
}

// Helper pour vérifier une ligne Ichimoku
void CheckAndAddResult(int symIdx, int bufferIdx, string lineName, double price, datetime now, int cooldown, ScanResult &res[], int &count)
{
   double val = GetIchiValue(g_symbolData[symIdx].ichimokuHandle, bufferIdx);
   if(val > 0)
   {
      double dev = ((price - val) / price) * 100.0;
      if(MathAbs(dev) <= InpThresholdPercent)
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
//| Interface Graphique                                              |
//+------------------------------------------------------------------+
void UpdateDashboard(ScanResult &data[], int count, long totalRam, long scriptRam, string tf)
{
   UpdateLabel(g_prefix+"h1", StringFormat("ICHIMOKU [%s] (Seuil: %.2f%%)", tf, InpThresholdPercent), 
               InpXOffset, InpYOffset, InpHeaderColor);
               
   string ramTxt = StringFormat("Term RAM: %d MB | Script: %d MB", totalRam, scriptRam);
   UpdateLabel(g_prefix+"ram", ramTxt, InpXOffset, InpYOffset + 15, (totalRam>InpMemWarningMB)?clrOrange:clrLime);
   
   UpdateLabel(g_prefix+"cols", "Symbole  | Prix     | Ligne  | Dist %", InpXOffset, InpYOffset + 30, clrWhite);
   
   int startY = InpYOffset + 50;
   int lineHeight = InpFontSize + 6;
   
   if(count == 0)
   {
      UpdateLabel(g_prefix+"row_0", "Recherche active...", InpXOffset, startY, clrGray);
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
   UpdateLabel(g_prefix+"h1", "!!! PAUSE RAM !!! Nettoyage en cours...", InpXOffset, InpYOffset, clrRed);
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
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
}

double GetIchiValue(int handle, int bufferIdx)
{
   if(handle == INVALID_HANDLE) return 0.0;
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if(CopyBuffer(handle, bufferIdx, 0, 1, buffer) <= 0) return 0.0;
   return buffer[0];
}

void SendAlert(string symbol, string line, double price, double diff, ENUM_TIMEFRAMES tf)
{
   if(!InpSendPush) return;
   string msg = StringFormat("ICHIMOKU %s: %s touchée sur %s (Ecart: %.2f%%)", 
                             StringSubstr(EnumToString(tf), 7), line, symbol, diff);
   SendNotification(msg);
}
