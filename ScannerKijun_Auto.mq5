//+------------------------------------------------------------------+
//|                                            ScannerKijun_Auto.mq5 |
//|                             Scanner Kijun-Sen (UT du Graphique)  |
//|                                                      MetaTrader 5|
//+------------------------------------------------------------------+
#property copyright "Généré par IA"
#property link      ""
#property version   "1.10"

//--- Inputs (Paramètres modifiables)
// Note : L'input "Timeframe" a été retiré. L'EA utilise celui du graphique.
input int             InpTenkan    = 9;         // Tenkan-sen
input int             InpKijun     = 26;        // Kijun-sen
input int             InpSenkouB   = 52;        // Senkou Span B
input bool            InpPopup     = true;      // Activer les alertes Popup
input bool            InpPush      = false;     // Activer les notifications Push (Mobile)

//--- Structure pour mémoriser l'état des alertes
struct SymbolState {
   string   name;
   datetime last_alert_time;
   ENUM_TIMEFRAMES last_tf; // On mémorise aussi le TF pour éviter les bugs si on change de vue
};

SymbolState symbols_state[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Timer de 5 secondes pour le scan
   EventSetTimer(5); 
   Print("Scanner Kijun démarré. Il suivra l'unité de temps de ce graphique.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Timer function (La boucle principale)                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Récupère l'UT actuelle du graphique sur lequel l'EA est posé
   ENUM_TIMEFRAMES currentTF = Period();
   
   // Boucle sur tous les symboles du Market Watch
   int total = SymbolsTotal(true); 
   
   for(int i = 0; i < total; i++)
   {
      string symbol = SymbolName(i, true);
      ScanSymbol(symbol, currentTF);
   }
}

//+------------------------------------------------------------------+
//| Fonction qui analyse un symbole spécifique                       |
//+------------------------------------------------------------------+
void ScanSymbol(string symbol, ENUM_TIMEFRAMES tf)
{
   // 1. Création du Handle Ichimoku avec le TF dynamique
   int handle = iCustom(symbol, tf, "Examples\\Ichimoku", InpTenkan, InpKijun, InpSenkouB);
   
   if(handle == INVALID_HANDLE) return;

   // 2. Buffers
   double kijun_buffer[];
   double close_price[];
   datetime time_buffer[];
   
   ArraySetAsSeries(kijun_buffer, true);
   ArraySetAsSeries(close_price, true);
   ArraySetAsSeries(time_buffer, true);

   // 3. Récupération des données
   // Si échec de la copie, on relâche le handle et on quitte
   if(CopyBuffer(handle, 1, 0, 3, kijun_buffer) < 3 || 
      CopyClose(symbol, tf, 0, 3, close_price) < 3 || 
      CopyTime(symbol, tf, 0, 1, time_buffer) < 1) 
   { 
      IndicatorRelease(handle); 
      return; 
   }

   // 4. Logique de Croisement
   // close[1] est la dernière bougie fermée, close[2] celle d'avant
   bool bullish_cross = (close_price[2] < kijun_buffer[2]) && (close_price[1] > kijun_buffer[1]);
   bool bearish_cross = (close_price[2] > kijun_buffer[2]) && (close_price[1] < kijun_buffer[1]);
   
   if(bullish_cross || bearish_cross)
   {
      // On passe aussi 'tf' pour gérer l'état (si on change de H1 à M15, on veut être alerté de nouveau)
      if(!AlreadyAlerted(symbol, time_buffer[0], tf)) 
      {
         string direction = bullish_cross ? "HAUSSIER (Buy)" : "BAISSIER (Sell)";
         
         // Message d'alerte clair
         string msg = StringFormat("KIJUN CROSS %s | %s | %s | Prix: %G", 
                                   direction, symbol, EnumToString(tf), close_price[1]);
         
         Print(msg);
         if(InpPopup) Alert(msg);
         if(InpPush)  SendNotification(msg);
         
         UpdateAlertState(symbol, time_buffer[0], tf);
      }
   }

   // Important : Libérer la mémoire
   IndicatorRelease(handle);
}

//+------------------------------------------------------------------+
//| Gestionnaire d'état anti-spam                                    |
//+------------------------------------------------------------------+
bool AlreadyAlerted(string symbol, datetime bar_time, ENUM_TIMEFRAMES tf)
{
   int size = ArraySize(symbols_state);
   for(int i=0; i<size; i++)
   {
      // On vérifie le Symbole ET l'heure ET le timeframe
      // Si on change de Timeframe, on considère que c'est une nouvelle configuration
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
         symbols_state[i].last_tf = tf; // Mise à jour du TF
         return;
      }
   }
   
   ArrayResize(symbols_state, size + 1);
   symbols_state[size].name = symbol;
   symbols_state[size].last_alert_time = bar_time;
   symbols_state[size].last_tf = tf;
}
//+------------------------------------------------------------------+
