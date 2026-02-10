//+------------------------------------------------------------------+
//|                            KijunScanner_Optimized.mq5            |
//|                                  Copyright 2026, Didier Le HPI Réunionnais    |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI Réunionnais"
#property link      "https://www.Didier-Le-HPI-Réunionnais.re"
#property version   "3.00"
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

input group "Gestion de la Mémoire (RAM)"
input int      InpMemWarningMB   = 500;    // Alerte RAM (Mo) - Orange
input int      InpMemPauseMB     = 800;    // Pause Scan (Mo) - Rouge
input int      InpPauseSeconds   = 60;     // Durée de la pause si critique (sec)

input group "Interface Graphique"
input int      InpXOffset        = 20;     // Position X
input int      InpYOffset        = 20;     // Position Y
input int      InpFontSize       = 9;      // Taille police (Optimisé)
input color    InpHeaderColor    = clrGold; 
input color    InpBgColor        = C'25,25,25'; // Couleur du fond plus sombre
input int      InpBgWidth        = 460;    // Largeur du panneau

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
};

//--- Variables globales
string      g_symbols[];
SymbolData  g_symbolData[]; 
int         g_totalSymbols = 0;
string      g_prefix = "ScanIchi_";

// Variables d'état
datetime    g_pauseEndTime = 0;
bool        g_isPaused = false;
int         g_lastRowCount = 0; // Pour optimiser le nettoyage graphique

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   InitSymbols();
   
   if(!InitHandles())
   {
      Print("Erreur critique : Impossible d'initialiser les indicateurs.");
      return(INIT_FAILED);
   }
   
   // Première vérification RAM
   CheckMemory();
   
   // Initialisation UI de base
   CreateBackground(InpXOffset - 5, InpYOffset - 5, InpBgWidth, 100); // Taille initiale
   
   EventSetTimer(InpScanSeconds);
   ScanMarket(); 
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialisation                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   // Suppression propre de tous les objets graphiques du script
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
         // Force un scan immédiat
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
   // CORRECTION MAJEURE : TERMINAL_MEMORY_USED retourne déjà des Mégaoctets (MB)
   long memUsedMB = TerminalInfoInteger(TERMINAL_MEMORY_USED); 
   
   if(memUsedMB >= InpMemPauseMB)
   {
      if(!g_isPaused)
      {
         g_isPaused = true;
         g_pauseEndTime = TimeCurrent() + InpPauseSeconds;
         Print("ALERTE RAM: ", memUsedMB, " Mo utilisés. Pause de ", InpPauseSeconds, "s.");
         UpdateMemoryStatusUI(); // Mise à jour immédiate de l'affichage
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
      // Récupère uniquement les symboles du Market Watch pour économiser la mémoire
      int total = SymbolsTotal(true); 
      ArrayResize(g_symbols, total);
      for(int i=0; i<total; i++) g_symbols[i] = SymbolName(i, true);
   }
   g_totalSymbols = ArraySize(g_symbols);
}

//+------------------------------------------------------------------+
//| Gestion des Handles (Indicateurs)                                |
//+------------------------------------------------------------------+
bool InitHandles()
{
   ArrayFree(g_symbolData);
   ArrayResize(g_symbolData, g_totalSymbols);
   
   for(int i = 0; i < g_totalSymbols; i++)
   {
      g_symbolData[i].name = g_symbols[i];
      // On crée le handle une seule fois ici
      g_symbolData[i].ichimokuHandle = iIchimoku(g_symbolData[i].name, _Period, InpTenkan, InpKijun, InpSenkou);
      
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
//| Cœur du Scanner                                                  |
//+------------------------------------------------------------------+
void ScanMarket()
{
   CheckMemory();
   if(g_isPaused) return;

   // Récupération RAM (Correction: Pas de division par 1024*1024 car déjà en Mo)
   long terminalRam = TerminalInfoInteger(TERMINAL_MEMORY_USED);
   long mqlRam = MQLInfoInteger(MQL_MEMORY_USED) / (1024 * 1024); // Celui-ci est en Bytes, donc on convertit

   ScanResult results[];
   // Pré-allocation optimiste pour éviter les redimensionnements excessifs
   ArrayResize(results, g_totalSymbols); 
   int count = 0;

   // --- BOUCLE DE SCAN ---
   for(int i = 0; i < g_totalSymbols; i++)
   {
      if(g_symbolData[i].ichimokuHandle == INVALID_HANDLE) continue;
      
      string symbol = g_symbolData[i].name;
      
      // Optimisation: Si symbole non dispo ou pas de tick, on passe vite
      if(!SymbolInfoInteger(symbol, SYMBOL_SELECT)) continue; 
      
      double price = SymbolInfoDouble(symbol, SYMBOL_BID);
      if(price <= 0) continue; // Données pas prêtes

      double kijun = GetKijunValue(g_symbolData[i].ichimokuHandle);
      if(kijun <= 0) continue;
      
      double deviation = ((price - kijun) / price) * 100.0;
      
      if(MathAbs(deviation) <= InpThresholdPercent)
      {
         results[count].sym = symbol;
         results[count].prc = price;
         results[count].diff = deviation;
         count++;
      }
   }
   
   // Redimensionner à la taille réelle des résultats pour économiser RAM
   ArrayResize(results, count);

   // --- MISE A JOUR UI (Optimisée) ---
   UpdateDashboard(results, count, terminalRam, mqlRam);
   
   ArrayFree(results); // Libération immédiate du tableau temporaire
}

//+------------------------------------------------------------------+
//| Gestion UI Optimisée (Mise à jour vs Suppression)                |
//+------------------------------------------------------------------+
void UpdateDashboard(ScanResult &data[], int count, long totalRam, long scriptRam)
{
   // 1. Header
   UpdateLabel(g_prefix+"h1", StringFormat("KIJUN SCANNER (Seuil: %.2f%%)", InpThresholdPercent), 
               InpXOffset, InpYOffset, InpHeaderColor, true);
               
   // 2. Info RAM Correcte
   color ramColor = (totalRam > InpMemWarningMB) ? clrOrange : clrLime;
   if(totalRam > InpMemPauseMB) ramColor = clrRed;
   
   string ramTxt = StringFormat("Term RAM: %d MB | Script: %d MB", totalRam, scriptRam);
   UpdateLabel(g_prefix+"ram", ramTxt, InpXOffset, InpYOffset + 15, ramColor);
   
   UpdateLabel(g_prefix+"sep", "--------------------------------------", InpXOffset, InpYOffset + 28, clrGray);

   int startY = InpYOffset + 45;
   int lineHeight = InpFontSize + 6;
   
   // 3. Affichage des lignes
   if(count == 0)
   {
      UpdateLabel(g_prefix+"row_0", "Aucune opportunité détectée...", InpXOffset, startY, clrGray);
      count = 1; // Pour garder au moins une ligne affichée
   }
   else
   {
      for(int i = 0; i < count; i++)
      {
         string trend = (data[i].diff > 0) ? "UP" : "DN";
         color txtColor = (data[i].diff > 0) ? clrLime : clrRed;
         string line = StringFormat("%-8s | %-8.5f | %+.2f%% | %s", 
                                    data[i].sym, data[i].prc, data[i].diff, trend);
         
         UpdateLabel(g_prefix+"row_"+(string)i, line, InpXOffset, startY + (i*lineHeight), txtColor);
      }
   }
   
   // 4. Nettoyage des lignes "fantômes" (si on avait 10 lignes avant et 2 maintenant)
   if(g_lastRowCount > count)
   {
      for(int k = count; k < g_lastRowCount; k++)
      {
         ObjectDelete(0, g_prefix+"row_"+(string)k);
      }
   }
   g_lastRowCount = count;
   
   // 5. Ajustement taille fond
   int bgH = 60 + (count * lineHeight);
   string bgName = g_prefix + "bg";
   if(ObjectFind(0, bgName) >= 0)
   {
      ObjectSetInteger(0, bgName, OBJPROP_YSIZE, bgH);
   }
   
   ChartRedraw();
}

void UpdateMemoryStatusUI()
{
   long ram = TerminalInfoInteger(TERMINAL_MEMORY_USED);
   int secLeft = (int)(g_pauseEndTime - TimeCurrent());
   if(secLeft < 0) secLeft = 0;
   
   string txt = StringFormat("!!! PAUSE RAM !!! (%d MB) - Reprise: %ds", ram, secLeft);
   UpdateLabel(g_prefix+"h1", txt, InpXOffset, InpYOffset, clrRed, true);
   
   // On cache les lignes pendant la pause critique
   for(int k=0; k<g_lastRowCount; k++) ObjectDelete(0, g_prefix+"row_"+(string)k);
   g_lastRowCount = 0;
   
   ChartRedraw();
}

//--- Helper pour créer ou mettre à jour un label sans le supprimer ---
void UpdateLabel(string name, string text, int x, int y, color clr, bool isHeader=false)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas"); // Police Monospace pour alignement
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   
   // On ne change les propriétés que si nécessaire (optimisation)
   if(ObjectGetString(0, name, OBJPROP_TEXT) != text)
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      
   if(ObjectGetInteger(0, name, OBJPROP_COLOR) != clr)
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
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
}

double GetKijunValue(int handle)
{
   if(handle == INVALID_HANDLE) return 0.0;
   
   double buffer[];
   // Optimisation mémoire : on ne demande que la dernière valeur
   if(CopyBuffer(handle, 1, 0, 1, buffer) != 1) return 0.0;
   
   double val = buffer[0];
   ArrayFree(buffer); // Libération immédiate
   return val;
}
//+------------------------------------------------------------------+
