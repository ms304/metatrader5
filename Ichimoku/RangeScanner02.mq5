//+------------------------------------------------------------------+
//|                            RangeScanner_BlackTheme_v2.0.mq5      |
//|                    Adaptation 2 Touches - Copyright 2026         |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI & AI Assistant"
#property version   "2.00"
#property strict

//--- INPUTS
input group "Paramètres du Range (2 Touches)"
input int      InpRangeBars      = 200;    // Profondeur d'analyse (bougies)
input double   InpTolerance      = 3.0;    // Tolérance en Pips pour les touches
input int      InpMinTouches     = 2;      // Minimum de touches (Haut et Bas)

input group "Optimisation & Mémoire"
input int      InpBatchSize      = 10;     // Nombre de symboles scannés par cycle
input int      InpSyncInterval   = 2;      // Intervalle timer (secondes)

input group "Interface (Thème Sombre)"
input color    InpBgColor        = C'20,20,20';    // Fond du dashboard (Gris très foncé)
input color    InpHeaderColor    = clrGold;        // Titre
input color    InpSuccessColor   = clrLime;        // Texte résultats
input color    InpWaitColor      = clrCyan;        // Texte en cours
input color    InpRangeColor     = clrDodgerBlue;  // Couleur du Rectangle sur le graph
input int      InpBorderSize     = 2;              // Epaisseur du rectangle
input int      InpXOffset        = 20;
input int      InpYOffset        = 20;
input int      InpMaxResults     = 20;     // Max résultats affichés sur le dash

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
   
   // Récupération des symboles du Market Watch
   int total = SymbolsTotal(true);
   if(ArrayResize(g_symbolsToScan, total) != total) return(INIT_FAILED);
   
   for(int i=0; i<total; i++) g_symbolsToScan[i] = SymbolName(i, true);
   g_totalToScan = total;

   PrintFormat(">> SCANNER : Démarrage du scan de %d actifs (Mode 2 Touches).", g_totalToScan);
   
   // UI de base
   CreateBackground();
   UpdateStatusUI();
   
   // Timer rapide pour le scan, puis ralentira une fois fini
   EventSetTimer(1); 
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Désinitialisation                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
   ObjectsDeleteAll(0, g_uiPrefix);
   ObjectsDeleteAll(0, g_prefix); // Optionnel : Supprimer les rectangles à la fermeture
}

//+------------------------------------------------------------------+
//| Timer Loop                                                       |
//+------------------------------------------------------------------+
void OnTimer() {
   if(!g_isScanFinished) {
      ExecuteScanBatch();
   } else {
      // Une fois le scan fini, on peut rafraîchir ou relancer ici si besoin
      // Pour l'instant on ne fait rien pour économiser les ressources
   }
}

//+------------------------------------------------------------------+
//| Exécution par lots (Batch)                                       |
//+------------------------------------------------------------------+
void ExecuteScanBatch() {
   int limit = MathMin(g_currentIdx + InpBatchSize, g_totalToScan);
   
   for(int i = g_currentIdx; i < limit; i++) {
      RangeData data;
      // Analyse Cœur
      if(AnalyzeSymbol(g_symbolsToScan[i], data)) {
         
         // Stockage
         int size = ArraySize(g_foundRanges);
         ArrayResize(g_foundRanges, size + 1);
         g_foundRanges[size] = data;
         
         // LOG EXPERT (Validé)
         PrintFormat(">>> RANGE DÉTECTÉ sur %s [%s] | Haut: %.5f (%d touches) | Bas: %.5f (%d touches)", 
                     data.symbol, EnumToString(_Period), data.high, data.touchesTop, data.low, data.touchesBottom);
         
         // Dessin immédiat si le chart est ouvert
         ApplyToChart(data);
         
         // Mise à jour visuelle liste
         ShowFinalResultsList(); 
      }
   }
   
   g_currentIdx = limit;
   UpdateStatusUI();
   
   // Fin du cycle
   if(g_currentIdx >= g_totalToScan) {
      g_isScanFinished = true;
      Print("<< SCAN TERMINÉ. Résultats affichés sur le graphique.");
      ArrayFree(g_symbolsToScan); 
      EventKillTimer(); // Stop le timer ou le mettre en mode lent
   }
}

//+------------------------------------------------------------------+
//| ANALYSE TECHNIQUE (Logique 2 Touches)                            |
//+------------------------------------------------------------------+
bool AnalyzeSymbol(string sym, RangeData &out) {
   double h[], l[];
   datetime t[];
   
   ArraySetAsSeries(h, true); 
   ArraySetAsSeries(l, true); 
   ArraySetAsSeries(t, true);
   
   // Récupération des données
   if(CopyHigh(sym, _Period, 0, InpRangeBars, h) < InpRangeBars) return false;
   if(CopyLow(sym, _Period, 0, InpRangeBars, l) < InpRangeBars) return false;
   if(CopyTime(sym, _Period, 0, InpRangeBars, t) < InpRangeBars) return false;
   
   // 1. Trouver les bornes absolues
   int idxHigh = ArrayMaximum(h, 0, InpRangeBars);
   int idxLow  = ArrayMinimum(l, 0, InpRangeBars);
   
   if(idxHigh == -1 || idxLow == -1) return false;
   
   double priceHigh = h[idxHigh];
   double priceLow  = l[idxLow];
   
   // Gestion des digits pour la tolérance
   long digits = SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double tolVal = InpTolerance * point;
   if(digits == 3 || digits == 5) tolVal *= 10;
   
   // 2. Compter les touches (Logique Fractale)
   int touchesTop = 0;
   int touchesBottom = 0;
   
   // On scanne (en évitant les bords pour le calcul i-1/i+1)
   for(int i = 1; i < InpRangeBars - 1; i++) {
      
      // -- Check Haut --
      if(MathAbs(h[i] - priceHigh) <= tolVal) {
         // Sommet local ?
         if(h[i] >= h[i+1] && h[i] >= h[i-1]) touchesTop++;
      }
      
      // -- Check Bas --
      if(MathAbs(l[i] - priceLow) <= tolVal) {
         // Creux local ?
         if(l[i] <= l[i+1] && l[i] <= l[i-1]) touchesBottom++;
      }
   }
   
   // 3. Validation
   if(touchesTop >= InpMinTouches && touchesBottom >= InpMinTouches) {
      out.symbol = sym;
      out.high   = priceHigh;
      out.low    = priceLow;
      out.start  = t[InpRangeBars-1]; // Début du range (passé)
      out.end    = t[0];              // Fin du range (présent)
      out.touchesTop = touchesTop;
      out.touchesBottom = touchesBottom;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Dessin sur les graphiques ouverts                                |
//+------------------------------------------------------------------+
void ApplyToChart(RangeData &data) {
   // On parcourt tous les graphiques ouverts dans MT5
   long chart = ChartFirst();
   int safety = 0;
   
   while(chart >= 0 && safety < 100) {
      // Si le symbole et l'UT correspondent
      if(ChartSymbol(chart) == data.symbol && ChartPeriod(chart) == _Period) {
         string name = g_prefix + "Rect";
         
         // Création ou Mise à jour
         if(ObjectFind(chart, name) < 0) {
            ObjectCreate(chart, name, OBJ_RECTANGLE, 0, 0, 0, 0, 0);
            ObjectSetInteger(chart, name, OBJPROP_COLOR, InpRangeColor);
            ObjectSetInteger(chart, name, OBJPROP_FILL, true);       // Rempli
            ObjectSetInteger(chart, name, OBJPROP_BACK, true);       // Arrière plan
            ObjectSetInteger(chart, name, OBJPROP_WIDTH, InpBorderSize);
         }
         
         // Coordonnées
         ObjectSetInteger(chart, name, OBJPROP_TIME, 0, data.start);
         ObjectSetDouble(chart, name, OBJPROP_PRICE, 0, data.high);
         ObjectSetInteger(chart, name, OBJPROP_TIME, 1, data.end);
         ObjectSetDouble(chart, name, OBJPROP_PRICE, 1, data.low);
         
         string tooltip = StringFormat("Range %s\nH: %.5f (x%d)\nL: %.5f (x%d)", 
                           data.symbol, data.high, data.touchesTop, data.low, data.touchesBottom);
         ObjectSetString(chart, name, OBJPROP_TOOLTIP, tooltip);
         
         ChartRedraw(chart);
      }
      chart = ChartNext(chart); 
      safety++;
   }
}

//+------------------------------------------------------------------+
//| Interface Graphique (Optimisée Noir)                             |
//+------------------------------------------------------------------+
void CreateBackground() {
   string name = g_uiPrefix + "BG";
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpXOffset - 5);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpYOffset - 5);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 230);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 40); 
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, InpBgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   
   // CORRECTION ICI : On utilise la couleur du fond pour masquer la bordure
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpBgColor); 
   
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

void UpdateStatusUI() {
   string name = g_uiPrefix + "status";
   string text = g_isScanFinished ? 
                 StringFormat("SCAN FINI | RANGES: %d", ArraySize(g_foundRanges)) :
                 StringFormat("SCAN EN COURS: %d/%d", g_currentIdx, g_totalToScan);
   
   color c = g_isScanFinished ? InpHeaderColor : InpWaitColor;
   CreateLabel(name, text, InpXOffset, InpYOffset, c, 10, true);
}

void ShowFinalResultsList() {
   int foundCount = ArraySize(g_foundRanges);
   int displayLimit = MathMin(foundCount, InpMaxResults);
   
   // Agrandir le fond noir dynamiquement
   ObjectSetInteger(0, g_uiPrefix+"BG", OBJPROP_YSIZE, 45 + (displayLimit * 18));

   for(int i=0; i<displayLimit; i++) {
      string name = g_uiPrefix + "list_" + (string)i;
      
      // Format: "1. EURUSD  [H:2 L:2]"
      string text = StringFormat("%d. %-8s (H:%d L:%d)", 
         i+1, g_foundRanges[i].symbol, g_foundRanges[i].touchesTop, g_foundRanges[i].touchesBottom);
         
      CreateLabel(name, text, InpXOffset, InpYOffset + 25 + (i*18), InpSuccessColor, 9, false);
   }
   ChartRedraw();
}

void CreateLabel(string name, string text, int x, int y, color clr, int fontSize, bool bold) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Black" : "Consolas");
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
}
