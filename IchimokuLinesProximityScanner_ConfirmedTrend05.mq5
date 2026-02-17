//+------------------------------------------------------------------+
//|                            KijunScanner_Massive_v4.64_Fixed.mq5  |
//|                                  Copyright 2026, Didier Le HPI   |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI Réunionnais"
#property link      "https://www.Didier-Le-HPI-Réunionnais.re"
#property version   "4.65_Persistent"
#property strict

//--- INPUTS
input group "Paramètres Ichimoku"
input ENUM_TIMEFRAMES InpScanTimeframe = PERIOD_CURRENT; 
input int      InpTenkan         = 9;      
input int      InpKijun          = 26;     
input int      InpSenkou         = 52;     

input group "Paramètres du Scanner (SCAN TOTAL)"
input int      InpBatchSize      = 10;     
input int      InpBatchDelay     = 1;      
input string   InpManualSymbols  = "";     
input double   InpThresholdPercent = 0.10; 

input group "Notifications Mobile"
input bool     InpSendPush       = true;   
input int      InpAlertCooldown  = 60;     

input group "Gestion de la Mémoire (RAM)"
input int      InpMemCriticalMB  = 1500;   

input group "Interface Graphique"
input int      InpXOffset        = 20;     
input int      InpYOffset        = 20;     
input int      InpFontSize       = 9;      
input color    InpHeaderColor    = clrGold; 
input color    InpBgColor        = C'25,25,25'; 
input int      InpMaxRowsDisplay = 40;     

//--- Structures
struct SymbolData {
   string name;
   int    ichimokuHandle; 
   datetime lastAlertTenkan, lastAlertKijun, lastAlertSSB;
};

struct ScanResult { 
   string sym; double prc; double diff; string line; 
};

//--- Variables globales
SymbolData      g_symbolData[]; 
int             g_totalSymbols = 0;
string          g_prefix = "ScanIchi_";
ENUM_TIMEFRAMES g_currentTF;

int             g_currentIdx = 0;         
ScanResult      g_accumulatedResults[];   
ScanResult      g_finalResultsForDisplay[]; 
int             g_accCount = 0;       
int             g_displayCount = 0;
int             g_lastRowCount = 0;

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   g_currentTF = (InpScanTimeframe == PERIOD_CURRENT) ? _Period : InpScanTimeframe;
   
   ResetScannerState();
   InitSymbolsList();
   
   if(g_totalSymbols <= 0) {
      Print("ERREUR: Aucun symbole valide trouvé !");
      return(INIT_FAILED);
   }

   UpdateLabel(g_prefix+"h1", "Synchronisation historique...", InpXOffset, InpYOffset, clrWhite);
   for(int i=0; i<g_totalSymbols; i++) {
      ForceDownloadHistory(g_symbolData[i].name, g_currentTF);
   }

   CreateBackground(InpXOffset - 5, InpYOffset - 5, 550, 100); 
   UpdateLabel(g_prefix+"h1", "Initialisation du scan...", InpXOffset, InpYOffset, clrWhite);
   
   EventSetTimer(InpBatchDelay);
   return(INIT_SUCCEEDED);
}

void ResetScannerState() {
   EventKillTimer();
   ObjectsDeleteAll(0, g_prefix);
   
   for(int i = 0; i < ArraySize(g_symbolData); i++) {
      if(g_symbolData[i].ichimokuHandle != INVALID_HANDLE) {
         IndicatorRelease(g_symbolData[i].ichimokuHandle);
      }
   }
   
   g_currentIdx = 0;
   g_accCount = 0;
   ArrayFree(g_accumulatedResults);
   ArrayFree(g_symbolData);
}

void OnDeinit(const int reason) {
   ResetScannerState();
}

//+------------------------------------------------------------------+
//| Timer - Scan par lots                                            |
//+------------------------------------------------------------------+
void OnTimer() {
   if(g_totalSymbols <= 0) return;
   if(TerminalInfoInteger(TERMINAL_MEMORY_USED) > InpMemCriticalMB) return;

   int limit = MathMin(g_currentIdx + InpBatchSize, g_totalSymbols);
   datetime now = TimeCurrent();
   int cooldownSec = InpAlertCooldown * 60;

   for(int i = g_currentIdx; i < limit; i++) {
      if(IsStopped()) return;
      string sym = g_symbolData[i].name;

      if(g_symbolData[i].ichimokuHandle == INVALID_HANDLE) {
         g_symbolData[i].ichimokuHandle = iIchimoku(sym, g_currentTF, InpTenkan, InpKijun, InpSenkou);
      }
      if(g_symbolData[i].ichimokuHandle == INVALID_HANDLE) continue;
      if(BarsCalculated(g_symbolData[i].ichimokuHandle) < 52) continue;

      double price = SymbolInfoDouble(sym, SYMBOL_BID);
      if(price <= 0) continue;

      double t = GetIchiValue(g_symbolData[i].ichimokuHandle, 0); 
      double k = GetIchiValue(g_symbolData[i].ichimokuHandle, 1); 
      double a = GetIchiValue(g_symbolData[i].ichimokuHandle, 2); 
      double b = GetIchiValue(g_symbolData[i].ichimokuHandle, 3); 

      if(t <= 0 || k <= 0 || a <= 0 || b <= 0) continue;

      CheckLogic(i, t, t, k, a, b, "Tenkan", price, now, cooldownSec);
      CheckLogic(i, k, t, k, a, b, "Kijun", price, now, cooldownSec);
      CheckLogic(i, b, t, k, a, b, "SSB", price, now, cooldownSec);
   }

   g_currentIdx = limit;
   UpdateLabel(g_prefix+"progress", StringFormat("Scan %s: %d / %d", StringSubstr(EnumToString(g_currentTF),7), g_currentIdx, g_totalSymbols), InpXOffset + 340, InpYOffset, clrCyan);

   if(g_currentIdx >= g_totalSymbols) {
      g_displayCount = MathMin(g_accCount, InpMaxRowsDisplay);
      ArrayResize(g_finalResultsForDisplay, g_displayCount);
      for(int r=0; r<g_displayCount; r++) g_finalResultsForDisplay[r] = g_accumulatedResults[r];
      
      UpdateDashboard();
      
      g_currentIdx = 0;
      // Note: On ne réinitialise PLUS g_accCount et g_accumulatedResults ici pour garder les actifs en mémoire
   }
}

//+------------------------------------------------------------------+
//| Logique - VERSION PERSISTANTE                                    |
//+------------------------------------------------------------------+
void CheckLogic(int symIdx, double lineVal, double t, double k, double a, double b, 
                string lineName, double price, datetime now, int cooldown) {
   double dev = ((price - lineVal) / price) * 100.0;
   
   // Si le prix touche ou est proche de la ligne
   if(MathAbs(dev) <= InpThresholdPercent) {
      bool isAligned = (price > lineVal) ? (price > t && price > k && price > a && price > b) 
                                         : (price < t && price < k && price < a && price < b);
      if(isAligned) {
         string currentSym = g_symbolData[symIdx].name;
         int foundIdx = -1;

         // On cherche si ce combo Symbole+Ligne existe déjà dans notre liste persistante
         for(int j=0; j<g_accCount; j++) {
            if(g_accumulatedResults[j].sym == currentSym && g_accumulatedResults[j].line == lineName) {
               foundIdx = j;
               break;
            }
         }

         // Si pas trouvé, on crée une nouvelle ligne dans le tableau
         if(foundIdx == -1) {
            g_accCount++;
            ArrayResize(g_accumulatedResults, g_accCount);
            foundIdx = g_accCount - 1;
         }

         // Mise à jour (ou remplissage) des données de l'actif
         g_accumulatedResults[foundIdx].sym = currentSym;
         g_accumulatedResults[foundIdx].prc = price;
         g_accumulatedResults[foundIdx].diff = dev;
         g_accumulatedResults[foundIdx].line = lineName;

         ManageAlerts(symIdx, lineName, price, dev, now, cooldown);
      }
   }
}

//+------------------------------------------------------------------+
//| Fonctions Utilitaires (Inchangées)                               |
//+------------------------------------------------------------------+
void InitSymbolsList() {
   if(InpManualSymbols != "") {
      string temp[]; ushort sep = StringGetCharacter(",", 0);
      int count = StringSplit(InpManualSymbols, sep, temp);
      g_totalSymbols = 0;
      ArrayResize(g_symbolData, count);
      for(int i=0; i<count; i++) {
         string s = temp[i]; StringTrimLeft(s); StringTrimRight(s);
         if(s != "" && SymbolInfoInteger(s, SYMBOL_SELECT)) {
            g_symbolData[g_totalSymbols].name = s;
            g_symbolData[g_totalSymbols].ichimokuHandle = INVALID_HANDLE;
            g_totalSymbols++;
         }
      }
      ArrayResize(g_symbolData, g_totalSymbols);
   } else {
      int total = SymbolsTotal(true); 
      g_totalSymbols = total;
      ArrayResize(g_symbolData, g_totalSymbols);
      for(int i=0; i<total; i++) {
         g_symbolData[i].name = SymbolName(i, true);
         g_symbolData[i].ichimokuHandle = INVALID_HANDLE;
      }
   }
}

void UpdateDashboard() {
   string tfStr = StringSubstr(EnumToString(g_currentTF), 7);
   UpdateLabel(g_prefix+"h1", "SCAN ICHIMOKU TOTAL - "+tfStr, InpXOffset, InpYOffset, InpHeaderColor);
   UpdateLabel(g_prefix+"ram", "Symboles détectés (total): "+(string)g_accCount, InpXOffset, InpYOffset+15, clrGray);
   
   int startY = InpYOffset + 50;
   int lineHeight = InpFontSize + 6;
   for(int i = 0; i < g_displayCount; i++) {
      color clr = (g_finalResultsForDisplay[i].diff >= 0) ? clrLime : clrRed;
      string line = StringFormat("%-8s | %-8.5f | %-6s | %+.2f%%", g_finalResultsForDisplay[i].sym, g_finalResultsForDisplay[i].prc, g_finalResultsForDisplay[i].line, g_finalResultsForDisplay[i].diff);
      UpdateLabel(g_prefix+"row_"+(string)i, line, InpXOffset, startY + (i*lineHeight), clr);
   }
   for(int k = g_displayCount; k < g_lastRowCount; k++) ObjectDelete(0, g_prefix+"row_"+(string)k);
   g_lastRowCount = g_displayCount;
   ObjectSetInteger(0, g_prefix+"bg", OBJPROP_YSIZE, 65 + (MathMax(1, g_displayCount) * lineHeight));
   ChartRedraw();
}

double GetIchiValue(int handle, int bufferIdx) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyBuffer(handle, bufferIdx, 0, 1, buffer) <= 0) return 0.0;
   return buffer[0];
}

void ForceDownloadHistory(string symbol, ENUM_TIMEFRAMES period) {
   datetime check[];
   CopyTime(symbol, period, 0, 100, check); 
}

void ManageAlerts(int i, string line, double price, double dev, datetime now, int cooldown) {
   bool a = false;
   if(line=="Tenkan" && now - g_symbolData[i].lastAlertTenkan > cooldown) { a=true; g_symbolData[i].lastAlertTenkan=now; }
   if(line=="Kijun" && now - g_symbolData[i].lastAlertKijun > cooldown)   { a=true; g_symbolData[i].lastAlertKijun=now; }
   if(line=="SSB" && now - g_symbolData[i].lastAlertSSB > cooldown)       { a=true; g_symbolData[i].lastAlertSSB=now; }
   if(a && InpSendPush) SendNotification(StringFormat("Ichimoku %s: %s sur %s (%.2f%%)", StringSubstr(EnumToString(g_currentTF),7), line, g_symbolData[i].name, dev));
}

void UpdateLabel(string name, string text, int x, int y, color clr) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas"); 
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
}

void CreateBackground(int x, int y, int w, int h) {
   string name = g_prefix + "bg";
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, InpBgColor);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
}
