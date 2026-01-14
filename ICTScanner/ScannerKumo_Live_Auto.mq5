//+------------------------------------------------------------------+
//|                                     ScannerKumo_Live_Fixed.mq5   |
//|               Scanner Nuage Ichimoku (Temps Réel / Bougie active)|
//|                                                      MetaTrader 5|
//+------------------------------------------------------------------+
#property copyright "Corrigé et Optimisé"
#property link      ""
#property version   "1.01"

//--- Inputs
input int             InpTenkan    = 9;         // Tenkan-sen
input int             InpKijun     = 26;        // Kijun-sen
input int             InpSenkouB   = 52;        // Senkou Span B
input bool            InpPopup     = true;      // Activer les alertes Popup
input bool            InpPush      = false;     // Activer les notifications Push (Mobile)

// Structure pour mémoriser l'état des alertes par symbole
struct SymbolState {
   string   name;
   datetime last_alert_time;
   ENUM_TIMEFRAMES last_tf;
};

SymbolState symbols_state[];

int OnInit()
{
   // Timer réglé sur 10 secondes pour éviter de surcharger le processeur
   // Scanner tous les symboles chaque seconde est trop lourd.
   EventSetTimer(10); 
   Print("Scanner Kumo (Nuage) LIVE démarré. Timer: 10s.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   // On utilise l'UT du graphique sur lequel l'EA est attaché
   ENUM_TIMEFRAMES currentTF = Period();
   
   // On scanne les symboles du Market Watch
   int total = SymbolsTotal(true); 
   
   for(int i = 0; i < total; i++)
   {
      string symbol = SymbolName(i, true);
      ScanSymbol(symbol, currentTF);
   }
}

void ScanSymbol(string symbol, ENUM_TIMEFRAMES tf)
{
   int handle = iIchimoku(symbol, tf, InpTenkan, InpKijun, InpSenkouB);
   if(handle == INVALID_HANDLE) return;

   double ssa_buffer[];   
   double ssb_buffer[];   
   double close_price[];  
   datetime time_buffer[];
   
   ArraySetAsSeries(ssa_buffer, true);
   ArraySetAsSeries(ssb_buffer, true);
   ArraySetAsSeries(close_price, true);
   ArraySetAsSeries(time_buffer, true);

   // --- CORRECTION CRITIQUE ICI ---
   // Pour le Prix : On lit à partir de 0 (le prix actuel)
   if(CopyClose(symbol, tf, 0, 2, close_price) < 2 || CopyTime(symbol, tf, 0, 1, time_buffer) < 1) { IndicatorRelease(handle); return; }

   // Pour le Nuage : On lit à partir de 'InpKijun' (26 périodes plus loin)
   // Car le nuage actuel (visuel) correspond aux données calculées il y a 26 bougies.
   if(CopyBuffer(handle, 2, InpKijun, 2, ssa_buffer) < 2 || 
      CopyBuffer(handle, 3, InpKijun, 2, ssb_buffer) < 2) 
   { 
      IndicatorRelease(handle); 
      return; 
   }
   // -------------------------------

   // Le reste de la logique reste identique, mais maintenant les données sont alignées !
   double cloud_top_0    = MathMax(ssa_buffer[0], ssb_buffer[0]);
   double cloud_bottom_0 = MathMin(ssa_buffer[0], ssb_buffer[0]);
   
   double cloud_top_1    = MathMax(ssa_buffer[1], ssb_buffer[1]);
   double cloud_bottom_1 = MathMin(ssa_buffer[1], ssb_buffer[1]);

   // --- Cassure HAUSSIÈRE ---
   bool bullish_breakout = (close_price[1] <= cloud_top_1) && (close_price[0] > cloud_top_0);
   
   // --- Cassure BAISSIÈRE ---
   bool bearish_breakout = (close_price[1] >= cloud_bottom_1) && (close_price[0] < cloud_bottom_0);
   
   if(bullish_breakout || bearish_breakout)
   {
      if(!AlreadyAlerted(symbol, time_buffer[0], tf)) 
      {
         string direction = bullish_breakout ? "HAUSSIER (Buy)" : "BAISSIER (Sell)";
         string msg = StringFormat("KUMO BREAKOUT %s | %s | %s | Prix: %.5f", direction, symbol, EnumToString(tf), close_price[0]);
         
         Print(msg);
         if(InpPopup) Alert(msg);
         if(InpPush)  SendNotification(msg);
         
         UpdateAlertState(symbol, time_buffer[0], tf);
      }
   }
   IndicatorRelease(handle);
}

// --- Fonctions de gestion d'état (CORRIGÉES) ---
bool AlreadyAlerted(string symbol, datetime bar_time, ENUM_TIMEFRAMES tf)
{
   int size = ArraySize(symbols_state);
   for(int i=0; i<size; i++)
   {
      if(symbols_state[i].name == symbol)
      {
         // Si c'est le bon symbole, on vérifie l'heure et le TF
         if(symbols_state[i].last_alert_time == bar_time && symbols_state[i].last_tf == tf) 
            return true; // Déjà alerté
         
         return false; // Symbole trouvé mais nouvelle bougie/TF -> Pas encore alerté
      }
   }
   // Symbole non trouvé dans la liste -> Pas encore alerté
   return false;
}

void UpdateAlertState(string symbol, datetime bar_time, ENUM_TIMEFRAMES tf)
{
   int size = ArraySize(symbols_state);
   for(int i=0; i<size; i++)
   {
      if(symbols_state[i].name == symbol)
      {
         // Mise à jour de l'existant
         symbols_state[i].last_alert_time = bar_time;
         symbols_state[i].last_tf = tf;
         return;
      }
   }
   // Ajout nouveau symbole
   ArrayResize(symbols_state, size + 1);
   symbols_state[size].name = symbol;
   symbols_state[size].last_alert_time = bar_time;
   symbols_state[size].last_tf = tf;
}
//+------------------------------------------------------------------+