//+------------------------------------------------------------------+
//|                                     ScannerKumo_Live_Auto.mq5    |
//|               Scanner Nuage Ichimoku (Temps Réel / Bougie active)|
//|                                                      MetaTrader 5|
//+------------------------------------------------------------------+
#property copyright "Généré par IA"
#property link      ""
#property version   "1.00"

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
   // Timer de 1 seconde pour scanner en temps réel
   EventSetTimer(1); 
   Print("Scanner Kumo (Nuage) LIVE démarré. Analyse des cassures de nuage en cours de formation.");
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
   
   // On scanne tous les symboles du Market Watch
   int total = SymbolsTotal(true); 
   
   for(int i = 0; i < total; i++)
   {
      string symbol = SymbolName(i, true);
      ScanSymbol(symbol, currentTF);
   }
}

void ScanSymbol(string symbol, ENUM_TIMEFRAMES tf)
{
   // 1. Initialisation de l'indicateur Ichimoku
   int handle = iCustom(symbol, tf, "Examples\\Ichimoku", InpTenkan, InpKijun, InpSenkouB);
   if(handle == INVALID_HANDLE) return;

   // 2. Buffers
   double ssa_buffer[];   // Senkou Span A
   double ssb_buffer[];   // Senkou Span B
   double close_price[];  // Prix actuel
   datetime time_buffer[];
   
   ArraySetAsSeries(ssa_buffer, true);
   ArraySetAsSeries(ssb_buffer, true);
   ArraySetAsSeries(close_price, true);
   ArraySetAsSeries(time_buffer, true);

   // 3. Récupération des données
   // Buffer 2 = Senkou Span A, Buffer 3 = Senkou Span B dans l'indicateur standard MT5
   if(CopyBuffer(handle, 2, 0, 2, ssa_buffer) < 2 || 
      CopyBuffer(handle, 3, 0, 2, ssb_buffer) < 2 ||
      CopyClose(symbol, tf, 0, 2, close_price) < 2 || 
      CopyTime(symbol, tf, 0, 1, time_buffer) < 1) 
   { 
      IndicatorRelease(handle); 
      return; 
   }

   // 4. Définition des bornes du Nuage (Kumo)
   // Le nuage est formé par l'espace entre SSA et SSB.
   // ATTENTION : SSA peut être > SSB ou inversement. Il faut trouver le Max et le Min.
   
   // Pour la bougie actuelle [0]
   double cloud_top_0    = MathMax(ssa_buffer[0], ssb_buffer[0]);
   double cloud_bottom_0 = MathMin(ssa_buffer[0], ssb_buffer[0]);
   
   // Pour la bougie précédente [1] (pour confirmer la cassure)
   double cloud_top_1    = MathMax(ssa_buffer[1], ssb_buffer[1]);
   double cloud_bottom_1 = MathMin(ssa_buffer[1], ssb_buffer[1]);

   // 5. Logique de Cassure de Nuage (Kumo Breakout)
   
   // --- Cassure HAUSSIÈRE (Kumo Breakout Bullish) ---
   // Le prix clôture précédente était SOUS ou DANS le nuage (<= Top précédent)
   // Le prix actuel est AU-DESSUS du nuage (> Top actuel)
   bool bullish_breakout = (close_price[1] <= cloud_top_1) && (close_price[0] > cloud_top_0);
   
   // --- Cassure BAISSIÈRE (Kumo Breakout Bearish) ---
   // Le prix clôture précédente était AU-DESSUS ou DANS le nuage (>= Bottom précédent)
   // Le prix actuel est EN-DESSOUS du nuage (< Bottom actuel)
   bool bearish_breakout = (close_price[1] >= cloud_bottom_1) && (close_price[0] < cloud_bottom_0);
   
   if(bullish_breakout || bearish_breakout)
   {
      // Vérification anti-spam pour la bougie actuelle
      if(!AlreadyAlerted(symbol, time_buffer[0], tf)) 
      {
         string direction = bullish_breakout ? "HAUSSIER (Sortie Nuage Haut)" : "BAISSIER (Sortie Nuage Bas)";
         
         string msg = StringFormat("KUMO BREAKOUT %s | %s | %s | Prix: %G", 
                                   direction, symbol, EnumToString(tf), close_price[0]);
         
         Print(msg);
         if(InpPopup) Alert(msg);
         if(InpPush)  SendNotification(msg);
         
         // Marquer comme traité
         UpdateAlertState(symbol, time_buffer[0], tf);
      }
   }

   // Libérer la mémoire du handle
   IndicatorRelease(handle);
}

// --- Fonctions de gestion d'état (Anti-Spam sur la même bougie) ---
bool AlreadyAlerted(string symbol, datetime bar_time, ENUM_TIMEFRAMES tf)
{
   int size = ArraySize(symbols_state);
   for(int i=0; i<size; i++)
   {
      if(symbols_state[i].name == symbol)
      {
         // Si on a déjà alerté pour cette heure de bougie ET ce timeframe
         if(symbols_state[i].last_alert_time == bar_time && symbols_state[i].last_tf == tf) return true;
         return false;
      }
   }
   return false;
}

void UpdateAlertState(string symbol, datetime bar_time, ENUM_TIMEFRAMES tf)
{
   int size = ArraySize(symbols_state);
   for(int i=0; i<size; i++)
   {
      if(symbols_state[i].name == symbol)
      {
         symbols_state[i].last_alert_time = bar_time;
         symbols_state[i].last_tf = tf;
         return;
      }
   }
   // Si le symbole n'est pas trouvé, on l'ajoute
   ArrayResize(symbols_state, size + 1);
   symbols_state[size].name = symbol;
   symbols_state[size].last_alert_time = bar_time;
   symbols_state[size].last_tf = tf;
}
//+------------------------------------------------------------------+
