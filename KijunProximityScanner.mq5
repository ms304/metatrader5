//+------------------------------------------------------------------+
//|                               Scanner_Ichimoku_Secure.mq5        |
//|                                  Copyright 2026, Didier le HPI    |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI"
#property link      "https://www.mql5.com"
#property version   "2.30"
#property strict

//--- INPUTS
input group "Paramètres Ichimoku"
input int      InpTenkan         = 9;      // Tenkan-sen
input int      InpKijun          = 26;     // Kijun-sen
input int      InpSenkou         = 52;     // Senkou Span B

input group "Paramètres du Scanner"
input string   InpManualSymbols  = "";     // Symboles (ex: EURUSD,GBPUSD) - Vide = Market Watch
input double   InpThresholdPercent = 0.10; // Seuil d'alerte en %
input int      InpScanSeconds    = 30;     // Fréquence du scan en secondes

input group "Interface Graphique"
input int      InpXOffset        = 20;     // Position X
input int      InpYOffset        = 20;     // Position Y
input int      InpFontSize       = 10;     // Taille police
input color    InpHeaderColor    = clrYellow; 
input color    InpBgColor        = C'30,30,30'; // Couleur du fond
input int      InpBgWidth        = 450;    // Largeur du panneau

//--- Structures pour la gestion mémoire sécurisée
struct SymbolData
{
   string name;
   int    ichimokuHandle; // On stocke le handle pour ne pas le recréer
};

//--- Variables globales
string      g_symbols[];
SymbolData  g_symbolData[]; // Tableau des structures (symbole + handle)
int         g_totalSymbols = 0;
string      g_prefix = "ScanIchi_";

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // 1. Initialisation des noms de symboles
   InitSymbols();
   
   // 2. Initialisation des handles d'indicateurs (Gestion mémoire optimisée)
   if(!InitHandles())
   {
      Print("Erreur critique lors de l'initialisation des handles.");
      return(INIT_FAILED);
   }
   
   EventSetTimer(InpScanSeconds);
   ScanMarket(); 
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialisation - Libération propre de la mémoire               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   
   // Suppression des objets graphiques
   ObjectsDeleteAll(0, g_prefix);
   
   // Libération CRUCIALE des handles d'indicateurs
   ReleaseHandles();
   
   // Libération des tableaux
   ArrayFree(g_symbols);
   ArrayFree(g_symbolData);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Timer                                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   ScanMarket();
}

//+------------------------------------------------------------------+
//| Initialise la liste des symboles                                 |
//+------------------------------------------------------------------+
void InitSymbols()
{
   ArrayFree(g_symbols); // Nettoyage avant remplissage
   
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
//| Initialise les handles d'indicateurs (Optimisation Mémoire)      |
//+------------------------------------------------------------------+
bool InitHandles()
{
   ArrayFree(g_symbolData);
   ArrayResize(g_symbolData, g_totalSymbols);
   
   for(int i = 0; i < g_totalSymbols; i++)
   {
      g_symbolData[i].name = g_symbols[i];
      // Création du handle UNE SEULE FOIS
      g_symbolData[i].ichimokuHandle = iIchimoku(g_symbolData[i].name, _Period, InpTenkan, InpKijun, InpSenkou);
      
      if(g_symbolData[i].ichimokuHandle == INVALID_HANDLE)
      {
         // CORRECTION ICI : Suppression des crochets parasites
         Print("Erreur création handle pour ", g_symbolData[i].name);
      }
   }
   return(true);
}

//+------------------------------------------------------------------+
//| Libère les handles pour éviter les fuites de mémoire             |
//+------------------------------------------------------------------+
void ReleaseHandles()
{
   int total = ArraySize(g_symbolData);
   for(int i = 0; i < total; i++)
   {
      if(g_symbolData[i].ichimokuHandle != INVALID_HANDLE)
      {
         IndicatorRelease(g_symbolData[i].ichimokuHandle);
         g_symbolData[i].ichimokuHandle = INVALID_HANDLE;
      }
   }
}

//+------------------------------------------------------------------+
//| Fonction principale de scan                                      |
//+------------------------------------------------------------------+
void ScanMarket()
{
   // On supprime tout pour reconstruire proprement
   ObjectsDeleteAll(0, g_prefix);
   
   int detectedCount = 0;
   
   // Utilisation d'une structure locale pour les résultats
   struct Result { string sym; double prc; double diff; };
   Result results[];
   
   // On alloue la mémoire nécessaire une seule fois
   ArrayResize(results, g_totalSymbols);

   for(int i = 0; i < g_totalSymbols; i++)
   {
      // Sécurité : vérifier si le handle est valide avant de l'utiliser
      if(g_symbolData[i].ichimokuHandle == INVALID_HANDLE) continue;
      
      string symbol = g_symbolData[i].name;
      double price = SymbolInfoDouble(symbol, SYMBOL_BID);
      
      if(price <= 0) continue;

      // On passe le handle déjà créé au lieu de le recréer
      double kijunValue = GetKijunValue(g_symbolData[i].ichimokuHandle);
      
      if(kijunValue <= 0) continue;
      
      double deviationPercent = ((price - kijunValue) / price) * 100.0;
      
      if(MathAbs(deviationPercent) <= InpThresholdPercent)
        {
         results[detectedCount].sym = symbol;
         results[detectedCount].prc = price;
         results[detectedCount].diff = deviationPercent;
         detectedCount++;
        }
     }

   // --- DESSIN DU FOND ---
   int lineH = InpFontSize + 8;
   int bgHeight = 40 + (MathMax(1, detectedCount) * lineH);
   CreateBackground(InpXOffset - 5, InpYOffset - 5, InpBgWidth, bgHeight);

   // --- DESSIN DES TEXTES ---
   UpdateDashboardHeader();
   
   if(detectedCount == 0)
     {
      CreateLabel(g_prefix+"none", "Aucune détection (Seuil " + DoubleToString(InpThresholdPercent, 2) + "%)", InpXOffset, InpYOffset + 30, clrGray);
     }
   else
     {
      for(int j = 0; j < detectedCount; j++)
        {
         UpdateDashboardRow(j, results[j].sym, results[j].prc, results[j].diff);
        }
     }
     
   ChartRedraw();
   
   // Optionnel : Libérer le tableau temporaire (bien que local, c'est une bonne pratique)
   ArrayFree(results); 
}

//+------------------------------------------------------------------+
//| Interface Graphique - Fond                                       |
//+------------------------------------------------------------------+
void CreateBackground(int x, int y, int w, int h)
{
   string name = g_prefix + "bg";
   if(ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
     {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, InpBgColor);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
}

void UpdateDashboardHeader()
{
   string text = StringFormat("SCANNER KIJUN (Seuil: %.2f%%)", InpThresholdPercent);
   CreateLabel(g_prefix+"h1", text, InpXOffset, InpYOffset, InpHeaderColor);
   CreateLabel(g_prefix+"h2", "--------------------------------------------------", InpXOffset, InpYOffset+15, InpHeaderColor);
}

void UpdateDashboardRow(int rowIdx, string symbol, double price, double diff)
{
   int y = InpYOffset + 35 + (rowIdx * (InpFontSize + 8));
   string trend = (diff > 0) ? "HAUT" : "BAS ";
   color  txtColor = (diff > 0) ? clrLime : clrRed;
   
   string text = StringFormat("%-10s | %-9.5f | %+.3f%% | %s", 
                              symbol, price, diff, trend);
   
   CreateLabel(g_prefix + "row_" + (string)rowIdx, text, InpXOffset, y, txtColor);
}

void CreateLabel(string name, string text, int x, int y, color clr)
{
   // Vérification si l'objet existe déjà pour éviter les erreurs logs (bien que DeleteAll soit appelé)
   if(ObjectFind(0, name) < 0)
     {
      if(ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
        {
         ObjectSetString(0, name, OBJPROP_TEXT, text);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
         ObjectSetString(0, name, OBJPROP_FONT, "Courier New");
         ObjectSetInteger(0, name, OBJPROP_ZORDER, 1); 
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        }
     }
   else
     {
      // Si l'objet existe (cas rare ici), on met juste à jour le texte
      ObjectSetString(0, name, OBJPROP_TEXT, text);
     }
}

//+------------------------------------------------------------------+
//| Récupère la Kijun (Version sécurisée avec Handle externe)        |
//+------------------------------------------------------------------+
double GetKijunValue(int handle)
{
   // Sécurité : Si le handle n'est pas valide, on retourne 0
   if(handle == INVALID_HANDLE) return 0.0;

   double buffer[];
   ArraySetAsSeries(buffer, true);
   
   // Copie des données depuis le handle pré-existant
   // On vérifie si la copie a réussi
   if(CopyBuffer(handle, 1, 0, 1, buffer) <= 0) return 0.0;
   
   // Plus besoin de IndicatorRelease ici, car géré globalement
   return buffer[0];
}
//+------------------------------------------------------------------+
