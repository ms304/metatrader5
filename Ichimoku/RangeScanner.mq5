//+------------------------------------------------------------------+
//|                            RangeScanner_BlackTheme_v1.6.mq5      |
//|                                  Copyright 2026, Didier Le HPI   |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI Réunionnais"
#property version   "1.60"
#property strict

//--- INPUTS
input group "Paramètres du Range"
input int      InpRangeBars      = 30;     
input double   InpMaxHeightPct   = 1.0;    
input int      InpADXThreshold   = 25;     

input group "Optimisation & Mémoire"
input int      InpBatchSize      = 10;     
input int      InpSyncInterval   = 2;      

input group "Interface (Thème Sombre)"
input color    InpBgColor        = C'20,20,20';    // Fond du dashboard (Gris très foncé)
input color    InpHeaderColor    = clrGold;        // Titre
input color    InpSuccessColor   = clrLime;        // Liste des résultats
input color    InpWaitColor      = clrCyan;        // En cours
input color    InpRangeColor     = clrDodgerBlue;  // Couleur des bordures du range
input int      InpBorderSize     = 2;              
input int      InpXOffset        = 20;
input int      InpYOffset        = 20;
input int      InpMaxResults     = 30;     

//--- Structures
struct RangeData {
   string   symbol;
   datetime start;
   datetime end;
   double   high;
   double   low;
};

//--- Variables Globales
string    g_symbolsToScan[];   
RangeData g_foundRanges[];     
int       g_totalToScan = 0;
int       g_currentIdx = 0;
bool      g_isScanFinished = false;
string    g_prefix = "RBox_";
string    g_uiPrefix = "RUI_";

//+------------------------------------------------------------------+
int OnInit() {
   ObjectsDeleteAll(0, g_uiPrefix);
   
   int total = SymbolsTotal(true);
   if(ArrayResize(g_symbolsToScan, total) != total) return(INIT_FAILED);
   
   for(int i=0; i<total; i++) g_symbolsToScan[i] = SymbolName(i, true);
   g_totalToScan = total;

   PrintFormat("Scanner : Démarrage du scan de %d actifs.", g_totalToScan);
   
   // Création du fond noir pour le Dashboard
   CreateBackground();
   
   EventSetTimer(1); 
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   EventKillTimer();
   ObjectsDeleteAll(0, g_uiPrefix);
}

void OnTimer() {
   if(!g_isScanFinished) ExecuteScanBatch();
   else SyncDrawingsToOpenCharts();
}

//+------------------------------------------------------------------+
void ExecuteScanBatch() {
   int limit = MathMin(g_currentIdx + InpBatchSize, g_totalToScan);
   for(int i = g_currentIdx; i < limit; i++) {
      RangeData data;
      if(AnalyzeSymbol(g_symbolsToScan[i], data)) {
         int size = ArraySize(g_foundRanges);
         ArrayResize(g_foundRanges, size + 1);
         g_foundRanges[size] = data;
         
         // LOG DANS LE SYSTÈME
         PrintFormat(">>> RANGE DÉTECTÉ : %s (Haut: %f | Bas: %f)", data.symbol, data.high, data.low);
         
         ApplyToChart(data);
      }
   }
   g_currentIdx = limit;
   UpdateStatusUI();
   
   if(g_currentIdx >= g_totalToScan) {
      g_isScanFinished = true;
      ArrayFree(g_symbolsToScan); 
      EventKillTimer();
      EventSetTimer(InpSyncInterval);
      ShowFinalResultsList();
   }
}

//+------------------------------------------------------------------+
bool AnalyzeSymbol(string sym, RangeData &out) {
   double h[], l[], c[], adx[];
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); 
   ArraySetAsSeries(c, true); ArraySetAsSeries(adx, true);
   
   if(CopyHigh(sym, _Period, 0, InpRangeBars, h) < InpRangeBars) return false;
   if(CopyLow(sym, _Period, 0, InpRangeBars, l) < InpRangeBars) return false;
   if(CopyClose(sym, _Period, 0, 1, c) < 1) return false;
   
   double high = h[ArrayMaximum(h)];
   double low  = l[ArrayMinimum(l)];
   double price = c[0];
   if(price <= 0) return false;
   
   if(((high - low) / price) * 100.0 > InpMaxHeightPct) return false;

   int handle = iADX(sym, _Period, 14);
   bool isRange = false;
   if(CopyBuffer(handle, 0, 0, 1, adx) > 0) { if(adx[0] < InpADXThreshold) isRange = true; }
   IndicatorRelease(handle);

   if(isRange) {
      out.symbol = sym; out.high = high; out.low = low;
      datetime t[]; ArraySetAsSeries(t, true);
      CopyTime(sym, _Period, 0, InpRangeBars, t);
      out.start = t[InpRangeBars-1]; out.end = t[0];
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void ApplyToChart(RangeData &data) {
   long chart = ChartFirst();
   int safety = 0;
   while(chart >= 0 && safety < 100) {
      if(ChartSymbol(chart) == data.symbol && ChartPeriod(chart) == _Period) {
         string name = g_prefix + data.symbol;
         if(ObjectFind(chart, name) < 0) {
            ObjectCreate(chart, name, OBJ_RECTANGLE, 0, data.start, data.high, data.end, data.low);
            ObjectSetInteger(chart, name, OBJPROP_COLOR, InpRangeColor);
            ObjectSetInteger(chart, name, OBJPROP_FILL, false);
            ObjectSetInteger(chart, name, OBJPROP_WIDTH, InpBorderSize);
            ObjectSetInteger(chart, name, OBJPROP_BACK, false);
            ChartRedraw(chart);
         }
      }
      chart = ChartNext(chart); safety++;
   }
}

//+------------------------------------------------------------------+
void SyncDrawingsToOpenCharts() {
   int count = ArraySize(g_foundRanges);
   for(int i=0; i<count; i++) ApplyToChart(g_foundRanges[i]);
}

//+------------------------------------------------------------------+
//| Interface Graphique (Optimisée Noir)                             |
//+------------------------------------------------------------------+
void CreateBackground() {
   string name = g_uiPrefix + "BG";
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpXOffset - 5);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpYOffset - 5);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 220);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 35); // Taille initiale
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, InpBgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void UpdateStatusUI() {
   string name = g_uiPrefix + "status";
   string text = g_isScanFinished ? 
                 StringFormat("✔ SCAN FINI | %d RANGES", ArraySize(g_foundRanges)) :
                 StringFormat("⌛ SCAN: %d/%d", g_currentIdx, g_totalToScan);
   CreateLabel(name, text, InpXOffset, InpYOffset, g_isScanFinished ? InpSuccessColor : InpWaitColor);
}

void ShowFinalResultsList() {
   int foundCount = ArraySize(g_foundRanges);
   int displayLimit = MathMin(foundCount, InpMaxResults);
   
   // Ajuster la taille du fond noir selon le nombre de résultats
   ObjectSetInteger(0, g_uiPrefix+"BG", OBJPROP_YSIZE, 45 + (displayLimit * 15));

   for(int i=0; i<displayLimit; i++) {
      string name = g_uiPrefix + "list_" + (string)i;
      string text = StringFormat("%d. %-10s [OK]", i+1, g_foundRanges[i].symbol);
      CreateLabel(name, text, InpXOffset, InpYOffset + 30 + (i*15), InpSuccessColor);
   }
   ChartRedraw();
}

void CreateLabel(string name, string text, int x, int y, color clr) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
}
