//+------------------------------------------------------------------+
//|                               Scanner_Ichimoku_Percent_Signed.mq5|
//|                                  Copyright 2026, Didier Le HPI    |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI"
#property link      "https://www.mql5.com"
#property version   "2.10"
#property strict

//--- INPUTS
input group "Paramètres Ichimoku"
input int      InpTenkan         = 9;      // Tenkan-sen
input int      InpKijun          = 26;     // Kijun-sen
input int      InpSenkou         = 52;     // Senkou Span B

input group "Paramètres du Scanner"
input string   InpManualSymbols  = "";     // Symboles (ex: EURUSD,GBPUSD) - Vide = Market Watch
input double   InpThresholdPercent = 0.10; // Seuil d'alerte en % (ex: 0.1)
input int      InpScanSeconds    = 30;     // Fréquence du scan en secondes

input group "Alertes"
input bool     InpUseAlert       = true;   // Alerte Pop-up
input bool     InpPrintLog       = true;   // Journal Expert
input bool     InpUsePush        = false;  // Alerte Push (Mobile)

input group "Interface Graphique"
input int      InpFontSize       = 10;     // Taille police
input color    InpHeaderColor    = clrYellow; 
input color    InpRowColor       = clrOrange; // Couleur des détections
input int      InpXOffset        = 20;     
input int      InpYOffset        = 20;     

//--- Variables globales
string g_symbols[];
int    g_totalSymbols = 0;
string g_prefix = "ScanIchi_";

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   InitSymbols();
   EventSetTimer(InpScanSeconds);
   ScanMarket(); // Premier scan
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, g_prefix);
  }

void OnTimer()
  {
   ScanMarket();
  }

//+------------------------------------------------------------------+
//| Initialise la liste des symboles                                 |
//+------------------------------------------------------------------+
void InitSymbols()
  {
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
//| Fonction principale de scan                                      |
//+------------------------------------------------------------------+
void ScanMarket()
  {
   // 1. Nettoyer les anciens objets du tableau avant le nouveau scan
   ObjectsDeleteAll(0, g_prefix);
   
   UpdateDashboardHeader();
   
   int detectedCount = 0; // Compteur de lignes affichées
   
   for(int i = 0; i < g_totalSymbols; i++)
     {
      string symbol = g_symbols[i];
      
      double price = SymbolInfoDouble(symbol, SYMBOL_BID);
      if(price <= 0) continue;

      double kijunValue = GetKijunValue(symbol);
      if(kijunValue <= 0) continue;
      
      // Calcul de l'écart en %
      double deviationPercent = ((price - kijunValue) / price) * 100.0;
      
      // --- FILTRE : On n'affiche que si on est sous le seuil ---
      if(MathAbs(deviationPercent) <= InpThresholdPercent)
        {
         // Ajout au tableau visuel
         UpdateDashboardRow(detectedCount, symbol, price, deviationPercent);
         detectedCount++;

         // Alertes (optionnel : une seule fois par bougie ou par scan)
         string msg = StringFormat("KIJUN : %s proche (%.3f%%)", symbol, deviationPercent);
         if(InpPrintLog) Print(msg);
         // Note: Alerte Pop-up peut être très répétitive ici si InpScanSeconds est bas
        }
     }
   
   // Si rien n'est trouvé
   if(detectedCount == 0)
     {
      CreateLabel(g_prefix+"none", "Aucun symbole sous le seuil " + DoubleToString(InpThresholdPercent, 2) + "%", InpXOffset, InpYOffset + 25, clrGray);
     }
     
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Interface Graphique                                              |
//+------------------------------------------------------------------+
void UpdateDashboardHeader()
  {
   string text = StringFormat("SYMBOLES PROCHES KIJUN (Seuil: %.2f%%)", InpThresholdPercent);
   CreateLabel(g_prefix+"header", text, InpXOffset, InpYOffset, InpHeaderColor);
   CreateLabel(g_prefix+"header2", "--------------------------------------------------", InpXOffset, InpYOffset+15, InpHeaderColor);
  }

void UpdateDashboardRow(int rowIdx, string symbol, double price, double diff)
  {
   // rowIdx permet d'empiler les lignes sans trous
   int y = InpYOffset + 30 + (rowIdx * (InpFontSize + 6));
   
   string trend = (diff > 0) ? "AU-DESSUS" : "EN-DESSOUS";
   color  txtColor = (diff > 0) ? clrLime : clrRed;
   
   string text = StringFormat("%-10s | Prix: %-9.5f | Écart: %+.3f%% | %s", 
                              symbol, price, diff, trend);
   
   CreateLabel(g_prefix + "row_" + (string)rowIdx, text, InpXOffset, y, txtColor);
  }

void CreateLabel(string name, string text, int x, int y, color clr)
  {
   if(ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
     {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Courier New");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
  }

//+------------------------------------------------------------------+
//| Récupère la Kijun                                                |
//+------------------------------------------------------------------+
double GetKijunValue(string symbol)
  {
   int handle = iIchimoku(symbol, _Period, InpTenkan, InpKijun, InpSenkou);
   if(handle == INVALID_HANDLE) return 0.0;
   
   double buffer[];
   ArraySetAsSeries(buffer, true);
   
   if(CopyBuffer(handle, 1, 0, 1, buffer) <= 0) 
     {
      IndicatorRelease(handle);
      return 0.0;
     }
   
   double result = buffer[0];
   IndicatorRelease(handle); 
   return result;
  }
