//+------------------------------------------------------------------+
//|                            KijunScanner_Optimized_v3.2.mq5       |
//|                                  Copyright 2026, Didier Le HPI Réunionnais    |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI Réunionnais"
#property link      "https://www.Didier-Le-HPI-Réunionnais.re"
#property version   "3.20"
#property strict

//--- INPUTS
input group "Paramètres Ichimoku"
input ENUM_TIMEFRAMES InpScanTimeframe = PERIOD_D1; // Timeframe à scanner (Force le Daily par défaut)
input int      InpTenkan         = 9;      // Tenkan-sen
input int      InpKijun          = 26;     // Kijun-sen
input int      InpSenkou         = 52;     // Senkou Span B

input group "Paramètres du Scanner"
input string   InpManualSymbols  = "";     // Symboles (ex: EURUSD,GBPUSD) - Vide = Market Watch
input double   InpThresholdPercent = 0.10; // Seuil d'alerte en %
input int      InpScanSeconds    = 30;     // Fréquence du scan en secondes

input group "Gestion de la Mémoire (RAM)"
input int      InpMemWarningMB   = 500;    // Alerte RAM (Mo) - Orange
input int      InpMemPauseMB     = 800;    // Pause Scan (Mo) - Rouge
input int      InpPauseSeconds   = 60;     // Durée de la pause si critique (sec)

input group "Interface Graphique"
input int      InpXOffset        = 20;     // Position X
input int      InpYOffset        = 20;     // Position Y
input int      InpFontSize       = 9;      // Taille police (Optimisé)
input color    InpHeaderColor    = clrGold; 
input color    InpBgColor        = C'25,25,25'; 
input int      InpBgWidth        = 550;    // Largeur ajustée

//--- Structures
struct SymbolData
{
   string name;
   int    ichimokuHandle; 
};

struct ScanResult 
{ 
   string sym; 
   double prc; 
   double diff; 
   string line; 
};

//--- Variables globales
string      g_symbols[];
SymbolData  g_symbolData[]; 
int         g_totalSymbols = 0;
string      g_prefix = "ScanIchi_";

// Variables d'état
datetime    g_pauseEndTime = 0;
bool        g_isPaused = false;
int         g_lastRowCount = 0; 

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   InitSymbols();
   
   // On utilise InpScanTimeframe au lieu de _Period pour garantir le TF choisi
   if(!InitHandles())
   {
      Print("Erreur critique : Impossible d'initialiser les indicateurs.");
      return(INIT_FAILED);
   }
   
   CheckMemory();
   CreateBackground(InpXOffset - 5, InpYOffset - 5, InpBgWidth, 100); 
   
   EventSetTimer(InpScanSeconds);
   // Premier scan différé légèrement pour laisser le temps aux handles de charger
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
      if(TimeCurrent() >= g_pauseEndTime)
      {
         g_isPaused = false;
         Print("RAM stabilisée. Reprise du scan.");
         ScanMarket();
      }
      else
      {
         UpdateMemoryStatusUI(); 
      }
      return;
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
         Print("ALERTE RAM: ", memUsedMB, " Mo utilisés. Pause.");
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
   ArrayResize(g_symbolData, g_totalSymbols);
   
   for(int i = 0; i < g_totalSymbols; i++)
   {
      g_symbolData[i].name = g_symbols[i];
      // FIX: Utilisation de InpScanTimeframe au lieu de _Period
      g_symbolData[i].ichimokuHandle = iIchimoku(g_symbolData[i].name, InpScanTimeframe, InpTenkan, InpKijun, InpSenkou);
      
      if(g_symbolData[i].ichimokuHandle == INVALID_HANDLE)
         Print("Warning: Handle invalide pour ", g_symbolData[i].name);
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
//| Helper: Vérification Disponibilité Données (CRUCIAL POUR DAILY)  |
//+------------------------------------------------------------------+
bool IsDataReady(string symbol, ENUM_TIMEFRAMES tf)
{
   // Vérifie si le terminal a assez de barres calculées
   if(Bars(symbol, tf) < 100) 
   {
      // Force le téléchargement/calcul
      datetime times[]; 
      CopyTime(symbol, tf, 0, 1, times); 
      return false;
   }
   return true;
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
   
   // Pour le scan Daily, le prix peut être éloigné, on vérifie que le prix est valide
   string tfString = EnumToString(InpScanTimeframe);
   string tfDisplay = StringSubstr(tfString, 7); // Enleve "PERIOD_"

   for(int i = 0; i < g_totalSymbols; i++)
   {
      if(g_symbolData[i].ichimokuHandle == INVALID_HANDLE) continue;
      
      string symbol = g_symbolData[i].name;
      
      // 1. Vérification selection et DONNÉES
      if(!SymbolInfoInteger(symbol, SYMBOL_SELECT)) continue; 
      if(!IsDataReady(symbol, InpScanTimeframe)) continue; // Saute si data pas prête (évite les erreurs 0.0)

      double price = SymbolInfoDouble(symbol, SYMBOL_BID);
      if(price <= 0) continue; 

      // --- 1. TEST TENKAN (Buffer 0) ---
      double tenkan = GetIchiValue(g_symbolData[i].ichimokuHandle, 0, symbol);
      if(tenkan > 0)
      {
         double devT = ((price - tenkan) / price) * 100.0;
         if(MathAbs(devT) <= InpThresholdPercent)
         {
            results[count].sym = symbol;
            results[count].prc = price;
            results[count].diff = devT;
            results[count].line = "Tenkan";
            count++;
         }
      }

      // --- 2. TEST KIJUN (Buffer 1) ---
      double kijun = GetIchiValue(g_symbolData[i].ichimokuHandle, 1, symbol);
      if(kijun > 0)
      {
         double devK = ((price - kijun) / price) * 100.0;
         if(MathAbs(devK) <= InpThresholdPercent)
         {
            results[count].sym = symbol;
            results[count].prc = price;
            results[count].diff = devK;
            results[count].line = "Kijun";
            count++;
         }
      }

      // --- 3. TEST SSB (Buffer 3) ---
      double ssb = GetIchiValue(g_symbolData[i].ichimokuHandle, 3, symbol);
      if(ssb > 0)
      {
         double devS = ((price - ssb) / price) * 100.0;
         if(MathAbs(devS) <= InpThresholdPercent)
         {
            results[count].sym = symbol;
            results[count].prc = price;
            results[count].diff = devS;
            results[count].line = "SSB";
            count++;
         }
      }
   }
   
   ArrayResize(results, count);
   UpdateDashboard(results, count, terminalRam, mqlRam, tfDisplay);
   ArrayFree(results); 
}

//+------------------------------------------------------------------+
//| Gestion UI                                                       |
//+------------------------------------------------------------------+
void UpdateDashboard(ScanResult &data[], int count, long totalRam, long scriptRam, string tf)
{
   // Header avec Timeframe affiché
   UpdateLabel(g_prefix+"h1", StringFormat("ICHIMOKU [%s] (Seuil: %.2f%%)", tf, InpThresholdPercent), 
               InpXOffset, InpYOffset, InpHeaderColor, true);
               
   string ramTxt = StringFormat("Term RAM: %d MB | Script: %d MB", totalRam, scriptRam);
   UpdateLabel(g_prefix+"ram", ramTxt, InpXOffset, InpYOffset + 15, (totalRam>InpMemWarningMB)?clrOrange:clrLime);
   
   UpdateLabel(g_prefix+"cols", "Symbole  | Prix     | Ligne  | Dist %", InpXOffset, InpYOffset + 30, clrWhite);
   UpdateLabel(g_prefix+"sep", "------------------------------------------", InpXOffset, InpYOffset + 40, clrGray);

   int startY = InpYOffset + 55;
   int lineHeight = InpFontSize + 6;
   
   if(count == 0)
   {
      UpdateLabel(g_prefix+"row_0", "Recherche ("+tf+")... Patience...", InpXOffset, startY, clrGray);
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
   
   int bgH = 70 + (count * lineHeight);
   string bgName = g_prefix + "bg";
   if(ObjectFind(0, bgName) >= 0) ObjectSetInteger(0, bgName, OBJPROP_YSIZE, bgH);
   ChartRedraw();
}

void UpdateMemoryStatusUI()
{
   long ram = TerminalInfoInteger(TERMINAL_MEMORY_USED);
   string txt = StringFormat("!!! PAUSE RAM !!! (%d MB)", ram);
   UpdateLabel(g_prefix+"h1", txt, InpXOffset, InpYOffset, clrRed, true);
}

void UpdateLabel(string name, string text, int x, int y, color clr, bool isHeader=false)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas"); 
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   if(ObjectGetString(0, name, OBJPROP_TEXT) != text) ObjectSetString(0, name, OBJPROP_TEXT, text);
   if(ObjectGetInteger(0, name, OBJPROP_COLOR) != clr) ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
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
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
}

//+------------------------------------------------------------------+
//| Récupération Valeur Ichi avec Gestion Erreur                     |
//+------------------------------------------------------------------+
double GetIchiValue(int handle, int bufferIdx, string symbol)
{
   if(handle == INVALID_HANDLE) return 0.0;
   
   double buffer[];
   // Reset de l'erreur
   ResetLastError();
   
   // Tentative de copie
   if(CopyBuffer(handle, bufferIdx, 0, 1, buffer) < 0)
   {
      // Erreur fréquente 4806 = Requested data not found
      int err = GetLastError();
      if(err == 4806 || err == 4807) 
      {
         // On ne spamme pas le journal, mais on sait que c'est un pb de data
         // Le scanner réessaiera au prochain tick
      }
      else
      {
         Print("Erreur CopyBuffer ", symbol, " Buffer: ", bufferIdx, " Erreur: ", err);
      }
      return 0.0;
   }
   
   return buffer[0];
}
//+------------------------------------------------------------------+
