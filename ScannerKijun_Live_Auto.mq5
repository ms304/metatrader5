//+------------------------------------------------------------------+
//|                                     ScannerKijun_Live_Auto.mq5   |
//|                  Scanner Kijun-Sen (Temps Réel / Bougie en cours)|
//|                                                      MetaTrader 5|
//+------------------------------------------------------------------+
#property copyright "Généré par IA"
#property link      ""
#property version   "1.20"

//--- Inputs
input int             InpTenkan    = 9;         // Tenkan-sen
input int             InpKijun     = 26;        // Kijun-sen
input int             InpSenkouB   = 52;        // Senkou Span B
input bool            InpPopup     = true;      // Activer les alertes Popup
input bool            InpPush      = false;     // Activer les notifications Push (Mobile)

struct SymbolState {
   string   name;
   datetime last_alert_time;
   ENUM_TIMEFRAMES last_tf;
};

SymbolState symbols_state[];

int OnInit()
{
   // Timer de 1 seconde pour être plus réactif en temps réel
   EventSetTimer(1); 
   Print("Scanner Kijun LIVE démarré. Analyse de la bougie en cours de formation.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   ENUM_TIMEFRAMES currentTF = Period();
   int total = SymbolsTotal(true); 
   
   for(int i = 0; i < total; i++)
   {
      string symbol = SymbolName(i, true);
      ScanSymbol(symbol, currentTF);
   }
}

void ScanSymbol(string symbol, ENUM_TIMEFRAMES tf)
{
   // 1. Handle Ichimoku
   int handle = iCustom(symbol, tf, "Examples\\Ichimoku", InpTenkan, InpKijun, InpSenkouB);
   if(handle == INVALID_HANDLE) return;

   // 2. Buffers
   double kijun_buffer[];
   double close_price[]; // Contiendra le prix actuel en [0]
   datetime time_buffer[];
   
   ArraySetAsSeries(kijun_buffer, true);
   ArraySetAsSeries(close_price, true);
   ArraySetAsSeries(time_buffer, true);

   // 3. Récupération des données (On commence à 0 pour avoir la bougie actuelle)
   // Nous n'avons besoin que de 2 valeurs : [0] (Actuel) et [1] (Précédent)
   if(CopyBuffer(handle, 1, 0, 2, kijun_buffer) < 2 || 
      CopyClose(symbol, tf, 0, 2, close_price) < 2 || 
      CopyTime(symbol, tf, 0, 1, time_buffer) < 1) 
   { 
      IndicatorRelease(handle); 
      return; 
   }

   // 4. Logique de Croisement TEMPS RÉEL
   // close_price[0] est le prix actuel (Bid/Last) tant que la bougie n'est pas finie.
   // close_price[1] est le prix de clôture de la bougie d'avant.
   // kijun_buffer[0] est la valeur actuelle de la Kijun.
   
   // Cross HAUSSIER : On était en dessous à la clôture précédente, on est au-dessus maintenant
   bool bullish_cross = (close_price[1] < kijun_buffer[1]) && (close_price[0] > kijun_buffer[0]);
   
   // Cross BAISSIER : On était au-dessus à la clôture précédente, on est en dessous maintenant
   bool bearish_cross = (close_price[1] > kijun_buffer[1]) && (close_price[0] < kijun_buffer[0]);
   
   if(bullish_cross || bearish_cross)
   {
      // On vérifie qu'on n'a pas déjà alerté POUR CETTE BOUGIE (time_buffer[0])
      if(!AlreadyAlerted(symbol, time_buffer[0], tf)) 
      {
         string direction = bullish_cross ? "HAUSSIER (Buy)" : "BAISSIER (Sell)";
         
         string msg = StringFormat("LIVE CROSS %s | %s | %s | Prix: %G", 
                                   direction, symbol, EnumToString(tf), close_price[0]);
         
         Print(msg);
         if(InpPopup) Alert(msg);
         if(InpPush)  SendNotification(msg);
         
         // On marque cette bougie comme "traitée" pour ne pas spammer si le prix repasse la ligne
         UpdateAlertState(symbol, time_buffer[0], tf);
      }
   }

   IndicatorRelease(handle);
}

// --- Fonctions de gestion d'état (Identiques à la version précédente) ---
bool AlreadyAlerted(string symbol, datetime bar_time, ENUM_TIMEFRAMES tf)
{
   int size = ArraySize(symbols_state);
   for(int i=0; i<size; i++)
   {
      if(symbols_state[i].name == symbol)
      {
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
   ArrayResize(symbols_state, size + 1);
   symbols_state[size].name = symbol;
   symbols_state[size].last_alert_time = bar_time;
   symbols_state[size].last_tf = tf;
}
//+------------------------------------------------------------------+
