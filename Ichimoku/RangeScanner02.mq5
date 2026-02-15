//+------------------------------------------------------------------+
//|                            RangeScanner_BlackTheme_v3.0.mq5      |
//|                    Adaptation 2 Touches - Copyright 2026         |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI & AI Assistant"
#property version   "3.00"
#property strict

//--- INPUTS
input group "Paramètres du Range (2 Touches)"
input int      InpRangeBars      = 200;    // Profondeur d'analyse (bougies)
input double   InpTolerance      = 5.0;    // Tolérance en Pips (H4: conseillé 10+)
input int      InpMinTouches     = 2;      // Minimum de touches (Haut et Bas)

input group "Optimisation & Mémoire"
input int      InpBatchSize      = 10;     // Symboles par cycle de scan
input int      InpRefreshRate    = 2;      // Maintenance des dessins (secondes)

input group "Interface (Thème Sombre)"
input color    InpBgColor        = C'20,20,20';    // Fond
input color    InpHeaderColor    = clrGold;        // Titre
input color    InpSuccessColor   = clrLime;        // Résultats
input color    InpWaitColor      = clrCyan;        // En cours
input color    InpRangeColor     = clrDodgerBlue;  // Couleur Rectangle
input int      InpBorderSize     = 2;              // Epaisseur
input int      InpMaxResults     = 20;             // Max affichés

//--- Structures
struct RangeData {
   string   symbol;
   datetime start;
   datetime end;
   double   high;
   double   low;
   int      touchesTop;
   int      touchesBottom;
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
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   ObjectsDeleteAll(0, g_uiPrefix);
   
   int total = SymbolsTotal(true);
   if(ArrayResize(g_symbolsToScan, total) != total) return(INIT_FAILED);
   
   for(int i=0; i<total; i++) g_symbolsToScan[i] = SymbolName(i, true);
   g_totalToScan = total;

   CreateBackground();
   UpdateStatusUI();
   
   EventSetTimer(1); 
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   EventKillTimer();
   ObjectsDeleteAll(0, g_uiPrefix);
   // On ne supprime pas g_prefix pour laisser les rectangles sur les autres charts
}

//+------------------------------------------------------------------+
//| Boucle Principale                                                |
//+------------------------------------------------------------------+
void OnTimer() {
   if(!g_isScanFinished) {
      ExecuteScanBatch();
   } else {
      // Une fois fini, on s'assure que les rectangles sont toujours là
      RefreshDrawings();
   }
}

//+------------------------------------------------------------------+
//| SCAN PAR LOTS                                                    |
//+------------------------------------------------------------------+
void ExecuteScanBatch() {
   int limit = MathMin(g_currentIdx + InpBatchSize, g_totalToScan);
   
   for(int i = g_currentIdx; i < limit; i++) {
      RangeData data;
      if(AnalyzeSymbol(g_symbolsToScan[i], data)) {
         int size = ArraySize(g_foundRanges);
         ArrayResize(g_foundRanges, size + 1);
         g_foundRanges[size] = data;
         
         // On applique immédiatement au graphique s'il est ouvert
         ApplyToChart(data);
         ShowFinalResultsList(); 
      }
   }
   
   g_currentIdx = limit;
   
   if(g_currentIdx >= g_totalToScan) {
      g_isScanFinished = true;
      EventKillTimer();
      EventSetTimer(InpRefreshRate); // Passe en mode maintenance lente
   }
   
   UpdateStatusUI();
}

//+------------------------------------------------------------------+
//| ANALYSE LOGIQUE                                                  |
//+------------------------------------------------------------------+
bool AnalyzeSymbol(string sym, RangeData &out) {
   double h[], l[];
   datetime t[];
   
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(t, true);
   
   if(CopyHigh(sym, _Period, 0, InpRangeBars, h) < InpRangeBars) return false;
   if(CopyLow(sym, _Period, 0, InpRangeBars, l) < InpRangeBars) return false;
   if(CopyTime(sym, _Period, 0, InpRangeBars, t) < InpRangeBars) return false;
   
   int idxHigh = ArrayMaximum(h, 0, InpRangeBars);
   int idxLow  = ArrayMinimum(l, 0, InpRangeBars);
   if(idxHigh == -1 || idxLow == -1) return false;
   
   double pHigh = h[idxHigh];
   double pLow  = l[idxLow];
   double rangeH = pHigh - pLow;

   // Calcul Tolérance adaptative
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double tolVal = InpTolerance * point;
   long digits = SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5) tolVal *= 10;
   
   // Sécurité : Le range doit être significatif (pas une ligne plate)
   if(rangeH < (tolVal * 5)) return false;

   int tTop = 0, tBot = 0;
   for(int i = 1; i < InpRangeBars - 1; i++) {
      if(MathAbs(h[i] - pHigh) <= tolVal && h[i] >= h[i+1] && h[i] >= h[i-1]) tTop++;
      if(MathAbs(l[i] - pLow) <= tolVal && l[i] <= l[i+1] && l[i] <= l[i-1]) tBot++;
   }
   
   if(tTop >= InpMinTouches && tBot >= InpMinTouches) {
      out.symbol = sym; out.high = pHigh; out.low = pLow;
      out.start = t[InpRangeBars-1]; out.end = t[0];
      out.touchesTop = tTop; out.touchesBottom = tBot;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| GESTION DES DESSINS                                              |
//+------------------------------------------------------------------+
void RefreshDrawings() {
   for(int i=0; i<ArraySize(g_foundRanges); i++) {
      ApplyToChart(g_foundRanges[i]);
   }
}

void ApplyToChart(RangeData &data) {
   long chart = ChartFirst();
   int safety = 0;
   
   while(chart >= 0 && safety < 100) {
      if(ChartSymbol(chart) == data.symbol) {
         // Nom unique par symbole pour éviter les conflits
         string name = g_prefix + data.symbol;
         
         if(ObjectFind(chart, name) < 0) {
            ObjectCreate(chart, name, OBJ_RECTANGLE, 0, 0, 0, 0, 0);
            ObjectSetInteger(chart, name, OBJPROP_COLOR, InpRangeColor);
            ObjectSetInteger(chart, name, OBJPROP_WIDTH, InpBorderSize);
            ObjectSetInteger(chart, name, OBJPROP_BACK, true);
            ObjectSetInteger(chart, name, OBJPROP_SELECTABLE, false);
         }
         
         // Mise à jour des points (Time 0 et 1, Price 0 et 1)
         ObjectSetInteger(chart, name, OBJPROP_TIME, 0, data.start);
         ObjectSetDouble(chart, name, OBJPROP_PRICE, 0, data.high);
         ObjectSetInteger(chart, name, OBJPROP_TIME, 1, data.end);
         ObjectSetDouble(chart, name, OBJPROP_PRICE, 1, data.low);
         
         ChartRedraw(chart);
      }
      chart = ChartNext(chart); 
      safety++;
   }
}

//+------------------------------------------------------------------+
//| INTERFACE GRAPHIQUE                                              |
//+------------------------------------------------------------------+
void CreateBackground() {
   string name = g_uiPrefix + "BG";
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 15);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 15);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 230);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 40); 
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, InpBgColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpBgColor); 
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void UpdateStatusUI() {
   string name = g_uiPrefix + "status";
   string text = g_isScanFinished ? 
                 StringFormat("SCAN TERMINE | RANGES: %d", ArraySize(g_foundRanges)) :
                 StringFormat("SCAN EN COURS: %d/%d", g_currentIdx, g_totalToScan);
   color c = g_isScanFinished ? InpHeaderColor : InpWaitColor;
   CreateLabel(name, text, 20, 20, c, 10, true);
}

void ShowFinalResultsList() {
   int displayLimit = MathMin(ArraySize(g_foundRanges), InpMaxResults);
   ObjectSetInteger(0, g_uiPrefix+"BG", OBJPROP_YSIZE, 45 + (displayLimit * 18));

   for(int i=0; i<displayLimit; i++) {
      string name = g_uiPrefix + "list_" + (string)i;
      string text = StringFormat("%d. %-10s (H:%d L:%d)", 
         i+1, g_foundRanges[i].symbol, g_foundRanges[i].touchesTop, g_foundRanges[i].touchesBottom);
      CreateLabel(name, text, 20, 45 + (i*18), InpSuccessColor, 9, false);
   }
   ChartRedraw();
}

void CreateLabel(string name, string text, int x, int y, color clr, int fontSize, bool bold) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Black" : "Consolas");
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
}
