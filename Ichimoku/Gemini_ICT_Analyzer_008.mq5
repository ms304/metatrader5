//+------------------------------------------------------------------+
//| GEMINI SMC PATTERN (RETRY 10 SECONDES SUR ERREUR 503)            |
//+------------------------------------------------------------------+
#property version "4.07"

input string API_KEY = "";

input int IntervalMin = 5;

// Remplacement de lastTime par nextCallTime pour un chronometre dynamique
datetime nextCallTime = 0; 
bool isFirstCall = true;

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
      // Se placer à la fin du fichier
      FileSeek(fileHandle, 0, SEEK_END);
      
      string separator = "\r\n================================================================================\r\n";
      string header = "[" + GetDateTimeString() + "]\r\n";
      
      // Écrire l'entête et la réponse complète
      FileWriteString(fileHandle, separator);
      FileWriteString(fileHandle, header);
      FileWriteString(fileHandle, response);
      FileWriteString(fileHandle, "\r\n");
      
      FileClose(fileHandle);
   }
   else
   {
      // Si le fichier n'existe pas, on le crée
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
int OnInit()
{
   Print("EA GEMINI SMC START");
   Print("========================================");
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("Attention: Le trading automatique est desactive.");

   CallGemini();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(TimeCurrent() >= nextCallTime)
   {
      CallGemini();
   }
}

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
string Clean(string s)
{
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\n", "\\n");
   StringReplace(s, "\r", "\\r");
   return s;
}

//+------------------------------------------------------------------+
//| Extraction COMPLETE de la réponse sans perte                     |
//+------------------------------------------------------------------+
string ExtractFullResponse(string jsonResponse)
{
   string result = "";
   
   // Chercher le début du texte
   int startPos = StringFind(jsonResponse, "\"text\": \"");
   if(startPos == -1) return jsonResponse;
   
   startPos += 9;
   
   // Trouver la fin en tenant compte des caractères échappés
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
   
   // Remplacer les séquences d'échappement
   StringReplace(result, "\\n", "\r\n");
   StringReplace(result, "\\r", "\r");
   StringReplace(result, "\\t", "\t");
   StringReplace(result, "\\\"", "\"");
   StringReplace(result, "\\\\", "\\");
   
   return result;
}

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
   "Look strictly for this specific setup: " +
   "1. Creation of a clear Buy Side Liquidity (BSL) swing high. " +
   "2. A sweep of a previous Sell Side Liquidity (SSL) swing low (price drops below a low but rejects/closes higher). " +
   "3. Market structure shifting upwards to target the BSL high. " +
   "If this exact pattern is confirmed and it is time to enter a LONG trade towards the BSL, return the details of your analysis and give the details of the detected conditions." +
   "And in this case give also the details of the trade with SL and TP." +
   "If the pattern is incomplete, invalid, or bearish, return the details of the conditions that are ok and the conditions that are still needed.";
   
   string json = "{\"contents\":[{\"parts\":[{\"text\":\"" + Clean(prompt) + "\"}]}]}";
   
   string req_headers = "Content-Type: application/json\r\n";
   string res_headers = "";
   char payload_in[], payload_out[];
   
   StringToCharArray(json, payload_in, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(payload_in, StringLen(json)); 

   ResetLastError();
   int res = WebRequest("POST", url, req_headers, 30000, payload_in, payload_out, res_headers); // Timeout augmenté à 30 secondes

   if(res == -1)
   {
      Print("Erreur WebRequest: ", GetLastError());
      nextCallTime = TimeCurrent() + 10;
      return;
   }

   string out = CharArrayToString(payload_out, 0, -1, CP_UTF8);
   
   // Afficher la taille de la réponse pour déboguer
   Print("Taille de la réponse JSON: ", StringLen(out), " caractères");
   
   // Extraire le texte complet de la réponse
   string finalResponse = ExtractFullResponse(out);
   
   // Afficher la taille du texte extrait
   Print("Taille du texte extrait: ", StringLen(finalResponse), " caractères");
   
   // --- LOG DE LA RÉPONSE COMPLÈTE ---
   LogResponse(finalResponse);
   
   // Affichage dans le terminal (début de la réponse)
   Print("========================================");
   Print("Reponse Gemini recue et loggee a ", TimeToString(TimeCurrent()));
   Print("Fichier: Gemini_Logs_" + GetDateString() + ".txt");
   Print("Debut de la reponse: ", StringSubstr(finalResponse, 0, 200), "...");
   Print("========================================");

   // Erreur 503 (Surcharge) ou 429 (Trop de requetes)
   if(res == 503 || res == 429)
   {
      Print("Serveurs Gemini surcharges (Code ", res, "). Nouvel essai dans 10 secondes...");
      nextCallTime = TimeCurrent() + 10;
      return; 
   }
   // Autres erreurs API critiques
   else if(res != 200)
   {
      Print("Erreur API Gemini fatale (Code ", res, "). Nouvel essai dans 1 minute.");
      nextCallTime = TimeCurrent() + 60;
      return; 
   }

   if(isFirstCall) 
   {
      Print("Contexte initial analyse par l'IA avec succes.");
      isFirstCall = false; 
   }
   
   nextCallTime = TimeCurrent() + (IntervalMin * 60);
   Print("Prochaine analyse dans ", IntervalMin, " minutes.");
}
