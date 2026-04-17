//+------------------------------------------------------------------+
//| GEMINI SMC PATTERN (RETRY 10 SECONDES SUR ERREUR 503)            |
//| AVEC TRADING LONG ET SHORT - VERSION 5.01                        |
//+------------------------------------------------------------------+
#property version "5.01"
#property copyright "Copyright 2025, SMC EA"

// --- Paramètres d'entrée ---
input string API_KEY = "Do lo i fann en boufate su la kaz mi ganye pa dormi";
input int IntervalMin = 5;
input double LotSize = 0.01;           // Taille de la position
input double RiskPercent = 1.0;        // Risque en % du capital (0 = lot fixe)
input int Slippage = 30;               // Slippage en points
input int MaxSpread = 50;              // Spread maximum autorisé (en points)
input bool UseBreakeven = true;        // Activer le breakeven
input int BreakevenPips = 50;          // Pips après lesquels passer en BE
input bool UseTrailingStop = true;     // Activer le trailing stop
input int TrailingStart = 30;          // Pips pour démarrer le trailing
input int TrailingStep = 15;           // Pas du trailing stop
input bool AllowPartialPattern = false; // Autoriser les patterns partiels
input bool DebugMode = true;            // Mode débogage (affiche tout)
input bool AllowLong = true;            // Autoriser les trades LONG
input bool AllowShort = true;           // Autoriser les trades SHORT

// --- NOUVEAU PARAMÈTRE : Distance maximale d'entrée ---
input int MaxEntryDistancePoints = 500; // Distance max entre prix actuel et entrée (en points, 500 points = 5 dollars pour XAUUSD)

// --- Variables globales ---
datetime nextCallTime = 0; 
bool isFirstCall = true;
ulong magicNumber = 20250417;          // Numéro magique pour identifier les trades

//+------------------------------------------------------------------+
//| Structure pour stocker les infos de trade                        |
//+------------------------------------------------------------------+
struct TradeInfo
{
   double entry;
   double sl;
   double tp;
   int direction; // 1 = LONG, -1 = SHORT
   bool hasTrade;
};
TradeInfo lastTrade = {0, 0, 0, 0, false};

//+------------------------------------------------------------------+
//| Fonction pour obtenir la date formatée YYYYMMDD                   |
//+------------------------------------------------------------------+
string GetDateString()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   return IntegerToString(dt.year) + 
          IntegerToString(dt.mon, 2, '0') + 
          IntegerToString(dt.day, 2, '0');
}

//+------------------------------------------------------------------+
//| Fonction pour formater la date et l'heure                        |
//+------------------------------------------------------------------+
string GetDateTimeString()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   return IntegerToString(dt.year) + "-" + 
          IntegerToString(dt.mon, 2, '0') + "-" + 
          IntegerToString(dt.day, 2, '0') + " " +
          IntegerToString(dt.hour, 2, '0') + ":" +
          IntegerToString(dt.min, 2, '0') + ":" +
          IntegerToString(dt.sec, 2, '0');
}

//+------------------------------------------------------------------+
//| Fonction pour loguer la réponse COMPLETE dans un fichier texte   |
//+------------------------------------------------------------------+
void LogResponse(string response)
{
   string fileName = "Gemini_Logs_" + GetDateString() + ".txt";
   
   int fileHandle = FileOpen(fileName, FILE_READ|FILE_WRITE|FILE_TXT);
   
   if(fileHandle != INVALID_HANDLE)
   {
      FileSeek(fileHandle, 0, SEEK_END);
      string separator = "\r\n================================================================================\r\n";
      string header = "[" + GetDateTimeString() + "]\r\n";
      
      FileWriteString(fileHandle, separator);
      FileWriteString(fileHandle, header);
      FileWriteString(fileHandle, response);
      FileWriteString(fileHandle, "\r\n");
      FileClose(fileHandle);
   }
   else
   {
      fileHandle = FileOpen(fileName, FILE_WRITE|FILE_TXT);
      if(fileHandle != INVALID_HANDLE)
      {
         string separator = "\r\n================================================================================\r\n";
         string header = "[" + GetDateTimeString() + "]\r\n";
         FileWriteString(fileHandle, separator);
         FileWriteString(fileHandle, header);
         FileWriteString(fileHandle, response);
         FileWriteString(fileHandle, "\r\n");
         FileClose(fileHandle);
      }
      else
      {
         Print("Erreur lors de l'ouverture du fichier de log : ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Fonction pour loguer les trades                                  |
//+------------------------------------------------------------------+
void LogTrade(string message)
{
   string fileName = "Gemini_Trades_" + GetDateString() + ".txt";
   
   int fileHandle = FileOpen(fileName, FILE_READ|FILE_WRITE|FILE_TXT);
   
   if(fileHandle != INVALID_HANDLE)
   {
      FileSeek(fileHandle, 0, SEEK_END);
      string logEntry = "[" + GetDateTimeString() + "] " + message + "\r\n";
      FileWriteString(fileHandle, logEntry);
      FileClose(fileHandle);
   }
   else
   {
      fileHandle = FileOpen(fileName, FILE_WRITE|FILE_TXT);
      if(fileHandle != INVALID_HANDLE)
      {
         string logEntry = "[" + GetDateTimeString() + "] " + message + "\r\n";
         FileWriteString(fileHandle, logEntry);
         FileClose(fileHandle);
      }
   }
}

//+------------------------------------------------------------------+
//| Calcul de la taille de lot dynamique                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
   if(RiskPercent <= 0 || slPips <= 0)
      return LotSize;
   
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (RiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slValue = slPips * point;
   
   if(tickValue == 0 || slValue == 0)
      return LotSize;
   
   double lot = riskAmount / (slValue * tickValue);
   
   // Arrondir au lot minimum autorisé
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0)
      lot = MathFloor(lot / lotStep) * lotStep;
   
   double lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lot < lotMin) lot = lotMin;
   if(lot > lotMax) lot = lotMax;
   
   return lot;
}

//+------------------------------------------------------------------+
//| Vérification des conditions de trading                          |
//+------------------------------------------------------------------+
bool CanTrade()
{
   // Vérifier si le trading auto est autorisé
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("Trading automatique non autorisé");
      return false;
   }
   
   // Vérifier le spread
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int currentSpread = (int)MathRound((ask - bid) / point);
   
   if(currentSpread > MaxSpread)
   {
      Print("Spread trop élevé: ", currentSpread, " > ", MaxSpread);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Exécution d'un trade LONG                                        |
//+------------------------------------------------------------------+
bool ExecuteLongTrade(double entry, double sl, double tp)
{
   if(!CanTrade() || !AllowLong)
      return false;
   
   // Vérifier si un trade similaire est déjà ouvert
   if(GetLastPositionTicket() > 0)
   {
      Print("Position déjà ouverte, pas de nouvelle entrée");
      return false;
   }
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Vérifier que le prix est cohérent
   if(ask > sl && sl > 0)
   {
      Print("ERREUR: Pour un LONG, le SL doit être en dessous du prix d'entrée");
      return false;
   }
   
   // Calcul du lot
   double slPips = MathAbs(entry - sl) / point;
   double lot = CalculateLotSize(slPips);
   
   // Préparation de la requête
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lot;
   request.type = ORDER_TYPE_BUY;
   request.price = ask;
   request.sl = sl;
   request.tp = tp;
   request.deviation = Slippage;
   request.magic = magicNumber;
   request.comment = "Gemini SMC Long";
   request.type_filling = ORDER_FILLING_FOK;
   
   Print("=== TENTATIVE DE TRADE LONG ===");
   Print("Entrée suggérée: ", entry);
   Print("Prix actuel: ", ask);
   Print("SL: ", sl);
   Print("TP: ", tp);
   Print("Lot: ", lot);
   Print("SL en points: ", slPips);
   Print("=================================");
   
   if(OrderSend(request, result))
   {
      Print("✓ Trade LONG exécuté avec succès! Ticket: ", result.order);
      LogTrade(StringFormat("LONG ENTRY: Prix=%.2f, SL=%.2f, TP=%.2f, Lot=%.2f, Ticket=%d", ask, sl, tp, lot, result.order));
      return true;
   }
   else
   {
      Print("✗ Erreur d'exécution LONG: ", GetLastError(), " - ", result.retcode_external);
      LogTrade(StringFormat("LONG FAILED: Erreur %d, Entry=%.2f, SL=%.2f, TP=%.2f", GetLastError(), entry, sl, tp));
      return false;
   }
}

//+------------------------------------------------------------------+
//| Exécution d'un trade SHORT                                       |
//+------------------------------------------------------------------+
bool ExecuteShortTrade(double entry, double sl, double tp)
{
   if(!CanTrade() || !AllowShort)
      return false;
   
   // Vérifier si un trade similaire est déjà ouvert
   if(GetLastPositionTicket() > 0)
   {
      Print("Position déjà ouverte, pas de nouvelle entrée");
      return false;
   }
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Vérifier que le prix est cohérent
   if(bid < sl && sl > 0)
   {
      Print("ERREUR: Pour un SHORT, le SL doit être au-dessus du prix d'entrée");
      return false;
   }
   
   // Calcul du lot
   double slPips = MathAbs(entry - sl) / point;
   double lot = CalculateLotSize(slPips);
   
   // Préparation de la requête
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lot;
   request.type = ORDER_TYPE_SELL;
   request.price = bid;
   request.sl = sl;
   request.tp = tp;
   request.deviation = Slippage;
   request.magic = magicNumber;
   request.comment = "Gemini SMC Short";
   request.type_filling = ORDER_FILLING_FOK;
   
   Print("=== TENTATIVE DE TRADE SHORT ===");
   Print("Entrée suggérée: ", entry);
   Print("Prix actuel: ", bid);
   Print("SL: ", sl);
   Print("TP: ", tp);
   Print("Lot: ", lot);
   Print("SL en points: ", slPips);
   Print("=================================");
   
   if(OrderSend(request, result))
   {
      Print("✓ Trade SHORT exécuté avec succès! Ticket: ", result.order);
      LogTrade(StringFormat("SHORT ENTRY: Prix=%.2f, SL=%.2f, TP=%.2f, Lot=%.2f, Ticket=%d", bid, sl, tp, lot, result.order));
      return true;
   }
   else
   {
      Print("✗ Erreur d'exécution SHORT: ", GetLastError(), " - ", result.retcode_external);
      LogTrade(StringFormat("SHORT FAILED: Erreur %d, Entry=%.2f, SL=%.2f, TP=%.2f", GetLastError(), entry, sl, tp));
      return false;
   }
}

//+------------------------------------------------------------------+
//| Récupère le ticket de la dernière position                       |
//+------------------------------------------------------------------+
ulong GetLastPositionTicket()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magicNumber)
         {
            return ticket;
         }
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Gestion du breakeven et trailing stop (adapte pour LONG et SHORT)|
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != magicNumber)
         continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl = PositionGetDouble(POSITION_SL);
      long type = PositionGetInteger(POSITION_TYPE);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double profitPips = (type == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / point : (openPrice - currentPrice) / point;
      
      // Breakeven
      if(UseBreakeven && profitPips >= BreakevenPips)
      {
         double newSL = openPrice + ((type == POSITION_TYPE_BUY) ? (5 * point) : (-5 * point));
         
         // Vérifier si le SL a changé
         if((type == POSITION_TYPE_BUY && newSL > sl) || (type == POSITION_TYPE_SELL && newSL < sl))
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.symbol = _Symbol;
            request.sl = newSL;
            request.tp = PositionGetDouble(POSITION_TP);
            
            if(OrderSend(request, result))
            {
               Print("Breakeven activé pour le ticket ", ticket);
               LogTrade(StringFormat("BREAKEVEN: Ticket=%d, Nouveau SL=%.2f", ticket, newSL));
            }
         }
      }
      // Trailing stop
      else if(UseTrailingStop && profitPips >= TrailingStart)
      {
         double newSL = 0;
         if(type == POSITION_TYPE_BUY)
            newSL = currentPrice - (TrailingStep * point);
         else
            newSL = currentPrice + (TrailingStep * point);
         
         if((type == POSITION_TYPE_BUY && newSL > sl) || (type == POSITION_TYPE_SELL && newSL < sl))
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.symbol = _Symbol;
            request.sl = newSL;
            request.tp = PositionGetDouble(POSITION_TP);
            
            if(OrderSend(request, result))
            {
               Print("Trailing stop mis à jour: ", newSL);
               LogTrade(StringFormat("TRAILING: Ticket=%d, Nouveau SL=%.2f", ticket, newSL));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Fermeture de toutes les positions                                |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magicNumber)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.position = ticket;
            request.deviation = Slippage;
            
            if(OrderSend(request, result))
            {
               Print("Position fermée: ", ticket);
               LogTrade(StringFormat("POSITION CLOSED: Ticket=%d", ticket));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Extraction améliorée des niveaux de trade (LONG et SHORT)        |
//+------------------------------------------------------------------+
bool ExtractTradeLevels(string response, double &entry, double &sl, double &tp, int &direction)
{
   entry = 0;
   sl = 0;
   tp = 0;
   direction = 0;
   
   // Déterminer la direction
   string upperResponse = response;
   StringToUpper(upperResponse);
   
   if(StringFind(upperResponse, "DECISION: LONG") >= 0)
      direction = 1;
   else if(StringFind(upperResponse, "DECISION: SHORT") >= 0)
      direction = -1;
   else
      return false;
   
   // Chercher Entry (plusieurs formats possibles)
   int entryPos = StringFind(response, "Entry:");
   if(entryPos == -1) entryPos = StringFind(response, "ENTRY:");
   if(entryPos == -1) entryPos = StringFind(response, "entry:");
   if(entryPos == -1) entryPos = StringFind(response, "Entrée:");
   
   if(entryPos >= 0)
   {
      string entryStr = "";
      for(int i = entryPos + 6; i < entryPos + 30 && i < StringLen(response); i++)
      {
         ushort ch = StringGetCharacter(response, i);
         if((ch >= '0' && ch <= '9') || ch == '.' || ch == ',')
         {
            entryStr += ShortToString(ch);
         }
         else if(ch == ' ' && StringLen(entryStr) > 0)
            break;
         else if(StringLen(entryStr) > 0 && (ch == '\n' || ch == '\r'))
            break;
      }
      StringReplace(entryStr, ",", ".");
      entry = StringToDouble(entryStr);
      if(DebugMode) Print("Entry extrait: ", entryStr, " -> ", entry);
   }
   
   // Chercher SL
   int slPos = StringFind(response, "SL:");
   if(slPos == -1) slPos = StringFind(response, "Stop Loss:");
   if(slPos == -1) slPos = StringFind(response, "sl:");
   
   if(slPos >= 0)
   {
      string slStr = "";
      int startOffset = (StringFind(response, "SL:") >= 0) ? 3 : 10;
      for(int i = slPos + startOffset; i < slPos + 30 && i < StringLen(response); i++)
      {
         ushort ch = StringGetCharacter(response, i);
         if((ch >= '0' && ch <= '9') || ch == '.' || ch == ',')
         {
            slStr += ShortToString(ch);
         }
         else if(ch == ' ' && StringLen(slStr) > 0)
            break;
         else if(StringLen(slStr) > 0 && (ch == '\n' || ch == '\r'))
            break;
      }
      StringReplace(slStr, ",", ".");
      sl = StringToDouble(slStr);
      if(DebugMode) Print("SL extrait: ", slStr, " -> ", sl);
   }
   
   // Chercher TP
   int tpPos = StringFind(response, "TP:");
   if(tpPos == -1) tpPos = StringFind(response, "Take Profit:");
   if(tpPos == -1) tpPos = StringFind(response, "tp:");
   
   if(tpPos >= 0)
   {
      string tpStr = "";
      int startOffset = (StringFind(response, "TP:") >= 0) ? 3 : 12;
      for(int i = tpPos + startOffset; i < tpPos + 30 && i < StringLen(response); i++)
      {
         ushort ch = StringGetCharacter(response, i);
         if((ch >= '0' && ch <= '9') || ch == '.' || ch == ',')
         {
            tpStr += ShortToString(ch);
         }
         else if(ch == ' ' && StringLen(tpStr) > 0)
            break;
         else if(StringLen(tpStr) > 0 && (ch == '\n' || ch == '\r'))
            break;
      }
      StringReplace(tpStr, ",", ".");
      tp = StringToDouble(tpStr);
      if(DebugMode) Print("TP extrait: ", tpStr, " -> ", tp);
   }
   
   // Vérifications de cohérence
   if(direction == 1 && entry > 0 && sl > 0 && tp > 0 && sl < entry)
      return true;
   if(direction == -1 && entry > 0 && sl > 0 && tp > 0 && sl > entry)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Détection du pattern LONG                                        |
//+------------------------------------------------------------------+
bool IsLongPatternValid(string response)
{
   string upperResponse = response;
   StringToUpper(upperResponse);
   
   // Vérifier d'abord que ce n'est pas WAIT
   if(StringFind(upperResponse, "DECISION: WAIT") >= 0)
      return false;
   
   // Vérifier les mots-clés de validité pour LONG
   return (StringFind(upperResponse, "DECISION: LONG") >= 0);
}

//+------------------------------------------------------------------+
//| Détection du pattern SHORT                                       |
//+------------------------------------------------------------------+
bool IsShortPatternValid(string response)
{
   string upperResponse = response;
   StringToUpper(upperResponse);
   
   // Vérifier d'abord que ce n'est pas WAIT
   if(StringFind(upperResponse, "DECISION: WAIT") >= 0)
      return false;
   
   // Vérifier les mots-clés de validité pour SHORT
   return (StringFind(upperResponse, "DECISION: SHORT") >= 0);
}

//+------------------------------------------------------------------+
//| Fonction existante GetData                                       |
//+------------------------------------------------------------------+
string GetData(int count)
{
   MqlRates r[]; 
   ArraySetAsSeries(r, true); 
   
   if(CopyRates(_Symbol, PERIOD_M5, 0, count, r) < count) 
   {
      Print("Erreur: Impossible de recuperer l'historique.");
      return "";
   }

   string s = "";
   for(int i = count - 1; i >= 0; i--)
   {
      s += "[H:" + DoubleToString(r[i].high, (int)Digits()) + 
           " L:" + DoubleToString(r[i].low, (int)Digits()) + 
           " C:" + DoubleToString(r[i].close, (int)Digits()) + "]";
      if(i > 0) s += ", ";
   }
   return s;
}

//+------------------------------------------------------------------+
//| Fonction existante Clean                                         |
//+------------------------------------------------------------------+
string Clean(string s)
{
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\n", "\\n");
   StringReplace(s, "\r", "\\r");
   return s;
}

//+------------------------------------------------------------------+
//| Fonction existante ExtractFullResponse                           |
//+------------------------------------------------------------------+
string ExtractFullResponse(string jsonResponse)
{
   string result = "";
   
   int startPos = StringFind(jsonResponse, "\"text\": \"");
   if(startPos == -1) return jsonResponse;
   
   startPos += 9;
   
   int endPos = startPos;
   int len = StringLen(jsonResponse);
   bool inEscape = false;
   
   for(int i = startPos; i < len; i++)
   {
      ushort ch = StringGetCharacter(jsonResponse, i);
      
      if(inEscape)
      {
         inEscape = false;
         continue;
      }
      
      if(ch == '\\')
      {
         inEscape = true;
         continue;
      }
      
      if(ch == '"')
      {
         endPos = i;
         break;
      }
   }
   
   if(endPos == startPos) return jsonResponse;
   
   result = StringSubstr(jsonResponse, startPos, endPos - startPos);
   
   StringReplace(result, "\\n", "\r\n");
   StringReplace(result, "\\r", "\r");
   StringReplace(result, "\\t", "\t");
   StringReplace(result, "\\\"", "\"");
   StringReplace(result, "\\\\", "\\");
   
   return result;
}

//+------------------------------------------------------------------+
//| Fonction principale CallGemini (avec trading LONG et SHORT)      |
//+------------------------------------------------------------------+
void CallGemini()
{
   int candlesToFetch = isFirstCall ? 48 : 10; 
   string data_str = GetData(candlesToFetch);
   
   if(data_str == "") 
   {
      nextCallTime = TimeCurrent() + 10;
      return;
   }

   string url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=" + API_KEY;
   string context = isFirstCall ? "4 hours of" : "last 10";
   
   string prompt = 
   "You are an expert SMC/ICT trader. Analyze this chronological sequence of " + context + " XAUUSD M5 candles " +
   "provided as High(H), Low(L), and Close(C): " + data_str + ". " +
   "Look strictly for these two setups:\n\n" +
   "=== LONG SETUP ===\n" +
   "1. Creation of a clear Buy Side Liquidity (BSL) swing high.\n" +
   "2. A sweep of a previous Sell Side Liquidity (SSL) swing low (price drops below a low but rejects/closes higher).\n" +
   "3. Market structure shifting upwards to target the BSL high.\n\n" +
   "=== SHORT SETUP ===\n" +
   "1. Creation of a clear Sell Side Liquidity (SSL) swing low.\n" +
   "2. A sweep of a previous Buy Side Liquidity (BSL) swing high (price rises above a high but rejects/closes lower).\n" +
   "3. Market structure shifting downwards to target the SSL low.\n\n" +
   "If a LONG setup is confirmed, respond EXACTLY in this format:\n" +
   "DECISION: LONG\n" +
   "ENTRY: X.XX\n" +
   "SL: X.XX\n" +
   "TP: X.XX\n" +
   "REASON: brief explanation\n\n" +
   "If a SHORT setup is confirmed, respond EXACTLY in this format:\n" +
   "DECISION: SHORT\n" +
   "ENTRY: X.XX\n" +
   "SL: X.XX\n" +
   "TP: X.XX\n" +
   "REASON: brief explanation\n\n" +
   "If no setup is confirmed, respond EXACTLY in this format:\n" +
   "DECISION: WAIT\n" +
   "REASON: brief explanation\n\n" +
   "Do not add any other text outside this format.";
   
   string json = "{\"contents\":[{\"parts\":[{\"text\":\"" + Clean(prompt) + "\"}]}]}";
   
   string req_headers = "Content-Type: application/json\r\n";
   string res_headers = "";
   char payload_in[], payload_out[];
   
   StringToCharArray(json, payload_in, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(payload_in, StringLen(json)); 

   ResetLastError();
   int res = WebRequest("POST", url, req_headers, 30000, payload_in, payload_out, res_headers);

   if(res == -1)
   {
      Print("Erreur WebRequest: ", GetLastError());
      nextCallTime = TimeCurrent() + 10;
      return;
   }

   string out = CharArrayToString(payload_out, 0, -1, CP_UTF8);
   
   if(DebugMode) Print("Taille de la réponse JSON: ", StringLen(out), " caractères");
   
   string finalResponse = ExtractFullResponse(out);
   
   if(DebugMode) Print("Taille du texte extrait: ", StringLen(finalResponse), " caractères");
   
   // --- LOG DE LA RÉPONSE COMPLÈTE ---
   LogResponse(finalResponse);
   
   Print("========================================");
   Print("Reponse Gemini recue a ", TimeToString(TimeCurrent()));
   Print("Fichier: Gemini_Logs_" + GetDateString() + ".txt");
   Print("Debut de la reponse: ", StringSubstr(finalResponse, 0, 300), "...");
   Print("========================================");

   // Gestion des erreurs API
   if(res == 503 || res == 429)
   {
      Print("Serveurs Gemini surcharges (Code ", res, "). Nouvel essai dans 10 secondes...");
      nextCallTime = TimeCurrent() + 10;
      return; 
   }
   else if(res != 200)
   {
      Print("Erreur API Gemini fatale (Code ", res, "). Nouvel essai dans 1 minute.");
      nextCallTime = TimeCurrent() + 60;
      return; 
   }

   // --- DEBUG : Afficher tout ce qui est détecté ---
   if(DebugMode)
   {
      Print("========== DEBUG EXTRACTION ==========");
      Print("Pattern LONG valide ? ", IsLongPatternValid(finalResponse));
      Print("Pattern SHORT valide ? ", IsShortPatternValid(finalResponse));
      
      double entryTest = 0, slTest = 0, tpTest = 0;
      int dirTest = 0;
      bool extracted = ExtractTradeLevels(finalResponse, entryTest, slTest, tpTest, dirTest);
      Print("Niveaux extraits: ", extracted);
      Print("Direction: ", dirTest == 1 ? "LONG" : (dirTest == -1 ? "SHORT" : "INCONNU"));
      Print("Entry: ", entryTest);
      Print("SL: ", slTest);
      Print("TP: ", tpTest);
      
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      Print("Prix actuel - Bid: ", bid, " Ask: ", ask);
      Print("Spread: ", (ask - bid) / point, " points");
      
      if(entryTest > 0)
      {
         if(dirTest == 1)
         {
            double distance = MathAbs(ask - entryTest) / point;
            Print("Distance entry/ask: ", distance, " points");
            Print("Seuil autorise: ", MaxEntryDistancePoints, " points");
            Print("Distance dans la limite: ", distance <= MaxEntryDistancePoints ? "OUI" : "NON");
         }
         else if(dirTest == -1)
         {
            double distance = MathAbs(bid - entryTest) / point;
            Print("Distance entry/bid: ", distance, " points");
            Print("Seuil autorise: ", MaxEntryDistancePoints, " points");
            Print("Distance dans la limite: ", distance <= MaxEntryDistancePoints ? "OUI" : "NON");
         }
      }
      
      ulong ticket = GetLastPositionTicket();
      Print("Trade déjà ouvert: ", ticket > 0 ? "OUI (Ticket " + IntegerToString(ticket) + ")" : "NON");
      Print("AllowLong: ", AllowLong ? "OUI" : "NON");
      Print("AllowShort: ", AllowShort ? "OUI" : "NON");
      Print("=======================================");
   }

   // --- TRADING : Vérifier les patterns LONG et SHORT ---
   bool tradeExecuted = false;
   
   // Vérifier LONG
   if(IsLongPatternValid(finalResponse) && AllowLong)
   {
      Print(">>> PATTERN LONG VALIDE DETECTE PAR GEMINI <<<");
      
      double entry = 0, sl = 0, tp = 0;
      int direction = 0;
      if(ExtractTradeLevels(finalResponse, entry, sl, tp, direction) && direction == 1)
      {
         Print("Niveaux extraits LONG - Entry: ", entry, " SL: ", sl, " TP: ", tp);
         
         bool alreadyExecuted = (GetLastPositionTicket() > 0);
         
         if(!alreadyExecuted && CanTrade())
         {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double distance = MathAbs(ask - entry) / point;
            
            if(distance <= MaxEntryDistancePoints)
            {
               Print("Exécution du trade LONG...");
               if(ExecuteLongTrade(entry, sl, tp))
               {
                  Print("✓ Trade LONG exécuté avec succès!");
                  tradeExecuted = true;
                  lastTrade.entry = entry;
                  lastTrade.sl = sl;
                  lastTrade.tp = tp;
                  lastTrade.direction = 1;
                  lastTrade.hasTrade = true;
               }
            }
            else
            {
               Print("Prix actuel (", ask, ") trop éloigné de l'entrée LONG suggérée (", entry, ")");
               Print("Distance: ", distance, " points > ", MaxEntryDistancePoints);
            }
         }
         else if(alreadyExecuted)
         {
            Print("Position déjà ouverte, pas de nouvelle entrée LONG");
         }
      }
      else
      {
         Print("Impossible d'extraire les niveaux LONG de la réponse Gemini");
      }
   }
   
   // Vérifier SHORT
   if(!tradeExecuted && IsShortPatternValid(finalResponse) && AllowShort)
   {
      Print(">>> PATTERN SHORT VALIDE DETECTE PAR GEMINI <<<");
      
      double entry = 0, sl = 0, tp = 0;
      int direction = 0;
      if(ExtractTradeLevels(finalResponse, entry, sl, tp, direction) && direction == -1)
      {
         Print("Niveaux extraits SHORT - Entry: ", entry, " SL: ", sl, " TP: ", tp);
         
         bool alreadyExecuted = (GetLastPositionTicket() > 0);
         
         if(!alreadyExecuted && CanTrade())
         {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double distance = MathAbs(bid - entry) / point;
            
            if(distance <= MaxEntryDistancePoints)
            {
               Print("Exécution du trade SHORT...");
               if(ExecuteShortTrade(entry, sl, tp))
               {
                  Print("✓ Trade SHORT exécuté avec succès!");
                  tradeExecuted = true;
                  lastTrade.entry = entry;
                  lastTrade.sl = sl;
                  lastTrade.tp = tp;
                  lastTrade.direction = -1;
                  lastTrade.hasTrade = true;
               }
            }
            else
            {
               Print("Prix actuel (", bid, ") trop éloigné de l'entrée SHORT suggérée (", entry, ")");
               Print("Distance: ", distance, " points > ", MaxEntryDistancePoints);
            }
         }
         else if(alreadyExecuted)
         {
            Print("Position déjà ouverte, pas de nouvelle entrée SHORT");
         }
      }
      else
      {
         Print("Impossible d'extraire les niveaux SHORT de la réponse Gemini");
      }
   }
   
   if(!tradeExecuted && (IsLongPatternValid(finalResponse) || IsShortPatternValid(finalResponse)))
   {
      Print("Pattern détecté mais exécution impossible (vérifier les logs)");
   }
   else if(!tradeExecuted)
   {
      Print(">>> AUCUN PATTERN VALIDE DETECTE PAR GEMINI <<<");
      Print("Aucun trade exécuté.");
   }

   if(isFirstCall) 
   {
      Print("Contexte initial analyse par l'IA avec succes.");
      isFirstCall = false; 
   }
   
   nextCallTime = TimeCurrent() + (IntervalMin * 60);
   Print("Prochaine analyse dans ", IntervalMin, " minutes.");
}

//+------------------------------------------------------------------+
//| Fonction OnInit                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("EA GEMINI SMC START - LONG ET SHORT");
   Print("Version 5.01 - Debug Mode: ", DebugMode ? "ON" : "OFF");
   Print("========================================");
   Print("Symbole: ", _Symbol);
   Print("Magic Number: ", magicNumber);
   Print("Lot size: ", LotSize);
   Print("Risk: ", RiskPercent, "%");
   Print("Allow Long: ", AllowLong ? "OUI" : "NON");
   Print("Allow Short: ", AllowShort ? "OUI" : "NON");
   Print("Allow Partial Pattern: ", AllowPartialPattern ? "OUI" : "NON");
   Print("Max Entry Distance: ", MaxEntryDistancePoints, " points");
   Print("========================================");
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("ATTENTION: Le trading automatique est desactive!");
   
   CallGemini();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Fonction OnTick                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   // Gérer les positions ouvertes (breakeven, trailing)
   ManagePositions();
   
   // Appeler Gemini à intervalles réguliers
   if(TimeCurrent() >= nextCallTime)
   {
      CallGemini();
   }
}

//+------------------------------------------------------------------+
//| Fonction OnDeinit                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA arrêté. Raison: ", reason);
   LogTrade(StringFormat("EA STOPPED: Reason=%d", reason));
}
//+------------------------------------------------------------------+
