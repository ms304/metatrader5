//+------------------------------------------------------------------+
//|                            KijunScanner_Cross_v4.65_Flats.mq5    |
//|                                  Copyright 2026, Didier Le HPI   |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI Réunionnais"
#property link      "https://www.Didier-Le-HPI-Réunionnais.re"
#property version   "4.65_Cross_Fixed"
#property strict

//--- INPUTS
input group "Paramètres Ichimoku"
input ENUM_TIMEFRAMES InpScanTimeframe = PERIOD_CURRENT; 
input int      InpTenkan         = 9;      
input int      InpKijun          = 26;     
input int      InpSenkou         = 52;     
input bool     InpUseTenkan      = true;   
input bool     InpUseKijun       = true;   
input bool     InpUseSSB         = true;   

input group "Détection des Plats Antérieurs"
input int      InpFlatLookback   = 150;    
input int      InpMinFlatBars    = 5;      
input bool     InpDetectFlats    = true;   

input group "Paramètres du Scanner (SCAN CROSS)"
input int      InpBatchSize      = 10;     
input int      InpBatchDelay     = 1;      
input string   InpManualSymbols  = "";     
input bool     InpScanCurrentCandle = false; // Scanner bougie en cours (B0) au lieu de (B1)

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
   datetime lastAlertTenkan, lastAlertKijun, lastAlertSSB, lastAlertFlat;
};

struct ScanResult { 
   string sym; double prc; double lvl; double diff; string line; 
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
   if(g_totalSymbols <= 0) return(INIT_FAILED);

   UpdateLabel(g_prefix+"h1", "Synchronisation historique...", InpXOffset, InpYOffset, clrWhite);
   for(int i=0; i<g_totalSymbols; i++) ForceDownloadHistory(g_symbolData[i].name, g_currentTF);

   CreateBackground(InpXOffset - 5, InpYOffset - 5, 600, 100); 
   EventSetTimer(InpBatchDelay);
   return(INIT_SUCCEEDED);
}

void ResetScannerState() {
   EventKillTimer();
   ObjectsDeleteAll(0, g_prefix);
   for(int i = 0; i < ArraySize(g_symbolData); i++) {
      if(g_symbolData[i].ichimokuHandle != INVALID_HANDLE) IndicatorRelease(g_symbolData[i].ichimokuHandle);
   }
   g_currentIdx = 0; g_accCount = 0;
   ArrayFree(g_accumulatedResults); ArrayFree(g_symbolData);
}

void OnDeinit(const int reason) { ResetScannerState(); }

//+------------------------------------------------------------------+
//| Timer - Scan par lots                                            |
//+------------------------------------------------------------------+
void OnTimer() {
   if(g_totalSymbols <= 0 || TerminalInfoInteger(TERMINAL_MEMORY_USED) > InpMemCriticalMB) return;

   int limit = MathMin(g_currentIdx + InpBatchSize, g_totalSymbols);
   datetime now = TimeCurrent();
   int cooldownSec = InpAlertCooldown * 60;
   
   // --- OPTION : Déterminer l'index à scanner
   int shift = InpScanCurrentCandle ? 0 : 1;

   for(int i = g_currentIdx; i < limit; i++) {
      string sym = g_symbolData[i].name;
      if(g_symbolData[i].ichimokuHandle == INVALID_HANDLE) 
         g_symbolData[i].ichimokuHandle = iIchimoku(sym, g_currentTF, InpTenkan, InpKijun, InpSenkou);
      
      if(g_symbolData[i].ichimokuHandle == INVALID_HANDLE || BarsCalculated(g_symbolData[i].ichimokuHandle) < InpFlatLookback) continue;

      // --- MODIFICATION : Utilisation du shift dynamique
      double openV  = iOpen(sym, g_currentTF, shift);
      double closeV = iClose(sym, g_currentTF, shift);
      
      double t = GetIchiValue(g_symbolData[i].ichimokuHandle, 0, shift); 
      double k = GetIchiValue(g_symbolData[i].ichimokuHandle, 1, shift); 
      double b = GetIchiValue(g_symbolData[i].ichimokuHandle, 3, shift); 

      if(t <= 0 || k <= 0 || openV <= 0) continue;

      if(InpUseTenkan) CheckLogic(i, t, openV, closeV, "Tenkan", now, cooldownSec);
      if(InpUseKijun)  CheckLogic(i, k, openV, closeV, "Kijun", now, cooldownSec);
      if(InpUseSSB)    CheckLogic(i, b, openV, closeV, "SSB", now, cooldownSec);

      if(InpDetectFlats) {
         if(InpUseTenkan) CheckHistoricalFlats(i, 0, "Tenkan(F)", openV, closeV, now, cooldownSec);
         if(InpUseKijun)  CheckHistoricalFlats(i, 1, "Kijun(F)", openV, closeV, now, cooldownSec);
         if(InpUseSSB)    CheckHistoricalFlats(i, 3, "SSB(F)", openV, closeV, now, cooldownSec);
      }
   }

   g_currentIdx = limit;
   UpdateLabel(g_prefix+"progress", StringFormat("Scan %s: %d / %d", StringSubstr(EnumToString(g_currentTF),7), g_currentIdx, g_totalSymbols), InpXOffset + 380, InpYOffset, clrCyan);

   if(g_currentIdx >= g_totalSymbols) {
      g_displayCount = MathMin(g_accCount, InpMaxRowsDisplay);
      ArrayResize(g_finalResultsForDisplay, g_displayCount);
      for(int r=0; r<g_displayCount; r++) g_finalResultsForDisplay[r] = g_accumulatedResults[r];
      UpdateDashboard();
      g_currentIdx = 0;
      g_accCount = 0; 
      ArrayFree(g_accumulatedResults);
   }
}

void CheckHistoricalFlats(int symIdx, int bufferIdx, string label, double openV, double closeV, datetime now, int cooldown) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyBuffer(g_symbolData[symIdx].ichimokuHandle, bufferIdx, 1, InpFlatLookback, buffer) < InpMinFlatBars) return;
   
   int count = 0;
   for(int j = 0; j < ArraySize(buffer) - 1; j++) {
      if(MathAbs(buffer[j] - buffer[j+1]) < _Point) {
         count++;
         if(count >= InpMinFlatBars - 1) {
            CheckLogic(symIdx, buffer[j], openV, closeV, label, now, cooldown);
            return; 
         }
      } else count = 0;
   }
}

void CheckLogic(int symIdx, double lineVal, double openV, double closeV, string lineName, datetime now, int cooldown) {
   bool bullCross = (openV < lineVal && closeV > lineVal);
   bool bearCross = (openV > lineVal && closeV < lineVal);

   if(bullCross || bearCross) {
      string currentSym = g_symbolData[symIdx].name;
      g_accCount++; 
      ArrayResize(g_accumulatedResults, g_accCount); 
      int newIdx = g_accCount - 1;

      g_accumulatedResults[newIdx].sym = currentSym;
      g_accumulatedResults[newIdx].prc = closeV;
      g_accumulatedResults[newIdx].lvl = lineVal; 
      g_accumulatedResults[newIdx].diff = (bullCross ? 1.0 : -1.0);
      g_accumulatedResults[newIdx].line = lineName;
      
      ManageAlerts(symIdx, lineName, closeV, g_accumulatedResults[newIdx].diff, now, cooldown);
   }
}

void UpdateDashboard() {
   string tfStr = StringSubstr(EnumToString(g_currentTF), 7);
   string bStr = InpScanCurrentCandle ? "B0" : "B1";
   UpdateLabel(g_prefix+"h1", "SCAN CROSS ICHIMOKU ("+bStr+") - "+tfStr, InpXOffset, InpYOffset, InpHeaderColor);
   UpdateLabel(g_prefix+"ram", "Signaux trouvés: "+(string)g_displayCount, InpXOffset, InpYOffset+15, clrGray);
   
   int startY = InpYOffset + 50;
   int lineHeight = InpFontSize + 6;
   for(int i = 0; i < g_displayCount; i++) {
      color clr = (g_finalResultsForDisplay[i].diff > 0) ? clrLime : clrRed;
      string direction = (g_finalResultsForDisplay[i].diff > 0) ? "CROSS UP" : "CROSS DN";
      string line = StringFormat("%-8s | P:%-8.5f | L:%-8.5f | %-10s | %s", 
                                 g_finalResultsForDisplay[i].sym, 
                                 g_finalResultsForDisplay[i].prc, 
                                 g_finalResultsForDisplay[i].lvl, 
                                 g_finalResultsForDisplay[i].line, 
                                 direction);
      UpdateLabel(g_prefix+"row_"+(string)i, line, InpXOffset, startY + (i*lineHeight), clr);
   }
   for(int k = g_displayCount; k < g_lastRowCount; k++) ObjectDelete(0, g_prefix+"row_"+(string)k);
   g_lastRowCount = g_displayCount;
   ObjectSetInteger(0, g_prefix+"bg", OBJPROP_YSIZE, 65 + (MathMax(1, g_displayCount) * lineHeight));
   ChartRedraw();
}

void InitSymbolsList() {
   if(InpManualSymbols != "") {
      string temp[]; ushort sep = StringGetCharacter(",", 0);
      int count = StringSplit(InpManualSymbols, sep, temp);
      g_totalSymbols = 0; ArrayResize(g_symbolData, count);
      for(int i=0; i<count; i++) {
         string s = temp[i]; StringTrimLeft(s); StringTrimRight(s);
         if(s != "" && SymbolInfoInteger(s, SYMBOL_SELECT)) {
            g_symbolData[g_totalSymbols].name = s; g_symbolData[g_totalSymbols].ichimokuHandle = INVALID_HANDLE;
            g_totalSymbols++;
         }
      }
      ArrayResize(g_symbolData, g_totalSymbols);
   } else {
      int total = SymbolsTotal(true); g_totalSymbols = total; ArrayResize(g_symbolData, g_totalSymbols);
      for(int i=0; i<total; i++) { g_symbolData[i].name = SymbolName(i, true); g_symbolData[i].ichimokuHandle = INVALID_HANDLE; }
   }
}

double GetIchiValue(int handle, int bufferIdx, int shift) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyBuffer(handle, bufferIdx, shift, 1, buffer) <= 0) return 0.0;
   return buffer[0];
}

void ForceDownloadHistory(string symbol, ENUM_TIMEFRAMES period) { datetime check[]; CopyTime(symbol, period, 0, 150, check); }

void ManageAlerts(int i, string line, double price, double dir, datetime now, int cooldown) {
   bool a = false;
   if(line=="Tenkan" && now - g_symbolData[i].lastAlertTenkan > cooldown) { a=true; g_symbolData[i].lastAlertTenkan=now; }
   if(line=="Kijun"  && now - g_symbolData[i].lastAlertKijun > cooldown)  { a=true; g_symbolData[i].lastAlertKijun=now; }
   if(line=="SSB"    && now - g_symbolData[i].lastAlertSSB > cooldown)    { a=true; g_symbolData[i].lastAlertSSB=now; }
   if(StringFind(line,"(F)") >= 0 && now - g_symbolData[i].lastAlertFlat > cooldown) { a=true; g_symbolData[i].lastAlertFlat=now; }
   
   string dStr = (dir > 0) ? "Cassure HAUSSIERE" : "Cassure BAISSIERE";
   if(a && InpSendPush) SendNotification(StringFormat("Ichimoku %s: %s %s sur %s", StringSubstr(EnumToString(g_currentTF),7), line, dStr, g_symbolData[i].name));
}

void UpdateLabel(string name, string text, int x, int y, color clr) {
   if(ObjectFind(0, name) < 0) { ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0); ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize); ObjectSetString(0, name, OBJPROP_FONT, "Consolas"); }
   ObjectSetString(0, name, OBJPROP_TEXT, text); ObjectSetInteger(0, name, OBJPROP_COLOR, clr); ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
}

void CreateBackground(int x, int y, int w, int h) {
   string name = g_prefix + "bg"; ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0); ObjectSetInteger(0, name, OBJPROP_BGCOLOR, InpBgColor);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y); ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
}
