//+------------------------------------------------------------------+
//|                            KijunScanner_Optimized_v3.1.mq5       |
//|                                  Copyright 2026, Didier Le HPI Réunionnais    |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property copyright "Didier Le HPI Réunionnais"
#property link      "https://www.Didier-Le-HPI-Réunionnais.re"
#property version   "3.10"
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
input int      InpBgWidth        = 500;    // Largeur du panneau (Augmentée pour afficher le nom de la ligne)

//--- Structures
struct SymbolData
{
   string name;
   int    ichimokuHandle; 
};

// Modification : Ajout du champ 'line' pour identifier Tenkan/Kijun/SSB
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
   
   if(!InitHandles())
   {
      Print("Erreur critique : Impossible d'initialiser les indicateurs.");
      return(INIT_FAILED);
   }
   
   CheckMemory();
   CreateBackground(InpXOffset - 5, InpYOffset - 5, InpBgWidth, 100); 
   
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
         Print("ALERTE RAM: ", memUsedMB, " Mo utilisés. Pause de ", InpPauseSeconds, "s.");
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
//| Cœur du Scanner (Modifié pour Tenkan, Kijun, SSB)                |
//+------------------------------------------------------------------+
void ScanMarket()
{
   CheckMemory();
   if(g_isPaused) return;

   long terminalRam = TerminalInfoInteger(TERMINAL_MEMORY_USED);
   long mqlRam = MQLInfoInteger(MQL_MEMORY_USED) / (1024 * 1024);

   ScanResult results[];
   // On prévoit large : chaque symbole peut potentiellement toucher les 3 lignes
   ArrayResize(results, g_totalSymbols * 3); 
   int count = 0;

   // --- BOUCLE DE SCAN ---
   for(int i = 0; i < g_totalSymbols; i++)
   {
      if(g_symbolData[i].ichimokuHandle == INVALID_HANDLE) continue;
      
      string symbol = g_symbolData[i].name;
      
      if(!SymbolInfoInteger(symbol, SYMBOL_SELECT)) continue; 
      
      double price = SymbolInfoDouble(symbol, SYMBOL_BID);
      if(price <= 0) continue; 

      // --- 1. TEST TENKAN (Buffer 0) ---
      double tenkan = GetIchiValue(g_symbolData[i].ichimokuHandle, 0);
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
      double kijun = GetIchiValue(g_symbolData[i].ichimokuHandle, 1);
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
      double ssb = GetIchiValue(g_symbolData[i].ichimokuHandle, 3);
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

   // --- MISE A JOUR UI ---
   UpdateDashboard(results, count, terminalRam, mqlRam);
   
   ArrayFree(results); 
}

//+------------------------------------------------------------------+
//| Gestion UI Optimisée                                             |
//+------------------------------------------------------------------+
void UpdateDashboard(ScanResult &data[], int count, long totalRam, long scriptRam)
{
   // 1. Header
   UpdateLabel(g_prefix+"h1", StringFormat("ICHIMOKU SCANNER (Seuil: %.2f%%)", InpThresholdPercent), 
               InpXOffset, InpYOffset, InpHeaderColor, true);
               
   // 2. Info RAM
   color ramColor = (totalRam > InpMemWarningMB) ? clrOrange : clrLime;
   if(totalRam > InpMemPauseMB) ramColor = clrRed;
   
   string ramTxt = StringFormat("Term RAM: %d MB | Script: %d MB", totalRam, scriptRam);
   UpdateLabel(g_prefix+"ram", ramTxt, InpXOffset, InpYOffset + 15, ramColor);
   
   // En-tête des colonnes
   UpdateLabel(g_prefix+"cols", "Symbole  | Prix     | Ligne  | Dist %", InpXOffset, InpYOffset + 30, clrWhite);
   UpdateLabel(g_prefix+"sep", "------------------------------------------", InpXOffset, InpYOffset + 40, clrGray);

   int startY = InpYOffset + 55;
   int lineHeight = InpFontSize + 6;
   
   // 3. Affichage des lignes
   if(count == 0)
   {
      UpdateLabel(g_prefix+"row_0", "Aucune opportunité détectée...", InpXOffset, startY, clrGray);
      count = 1; 
   }
   else
   {
      for(int i = 0; i < count; i++)
      {
         color txtColor = (data[i].diff >= 0) ? clrLime : clrRed; // Vert si prix > ligne, Rouge si prix < ligne
         
         // Formatage avec alignement : Symbole | Prix | Ligne | %Diff
         string lineStr = StringFormat("%-8s | %-8.5f | %-6s | %+.2f%%", 
                                    data[i].sym, data[i].prc, data[i].line, data[i].diff);
         
         UpdateLabel(g_prefix+"row_"+(string)i, lineStr, InpXOffset, startY + (i*lineHeight), txtColor);
      }
   }
   
   // 4. Nettoyage
   if(g_lastRowCount > count)
   {
      for(int k = count; k < g_lastRowCount; k++)
      {
         ObjectDelete(0, g_prefix+"row_"+(string)k);
      }
   }
   g_lastRowCount = count;
   
   // 5. Ajustement taille fond
   int bgH = 70 + (count * lineHeight);
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
   
   for(int k=0; k<g_lastRowCount; k++) ObjectDelete(0, g_prefix+"row_"+(string)k);
   g_lastRowCount = 0;
   
   ChartRedraw();
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

// Nouvelle fonction générique pour récupérer n'importe quel buffer Ichimoku
// Buffer 0 = Tenkan, 1 = Kijun, 3 = SSB
double GetIchiValue(int handle, int bufferIdx)
{
   if(handle == INVALID_HANDLE) return 0.0;
   
   double buffer[];
   if(CopyBuffer(handle, bufferIdx, 0, 1, buffer) != 1) return 0.0;
   
   double val = buffer[0];
   ArrayFree(buffer); 
   return val;
}
//+------------------------------------------------------------------+
