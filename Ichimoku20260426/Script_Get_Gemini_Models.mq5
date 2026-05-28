//+------------------------------------------------------------------+
//|                                              GeminiModelsAPI.mq5 |
//|                                    Appelle l'API Gemini Models   |  NE FONCTIONNE PAS ENCORE
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property script_show_inputs

// Paramètres d'entrée
input string ApiKey = "replace me";  // Clé API Gemini
input bool ShowAllDetails = true;  // Afficher tous les détails

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    // Vérifier que la clé API n'est pas vide
    if(StringLen(ApiKey) == 0)
    {
        Print("ERREUR: Veuillez entrer une clé API valide dans les paramètres!");
        return;
    }
    
    // Construire l'URL avec la clé API
    string url = "https://generativelanguage.googleapis.com/v1beta/models?key=" + ApiKey;
    
    Print("=== Début de l'appel API Gemini Models ===");
    Print("URL: ", url);
    
    // Préparer la requête - Version CORRECTE pour WebRequest
    string headers = "Content-Type: application/json\r\n";
    char postData[];
    char resultData[];
    string response;
    
    int timeout = 10000; // 10 secondes de timeout
    
    // WebRequest avec la signature correcte (5 paramètres)
    int res = WebRequest("GET", url, headers, timeout, postData, resultData, response);
    
    if(res == -1)
    {
        Print("Erreur WebRequest: ", GetLastError());
        Print("Vérifiez que WebRequest est autorisé:");
        Print("Outils -> Options -> Experts -> Autoriser les requêtes WebRequest");
        Print("Ajoutez l'URL: https://generativelanguage.googleapis.com/*");
        return;
    }
    
    if(res == 200)
    {
        Print("Succès! Code HTTP: ", res);
        Print("Taille de la réponse: ", StringLen(response), " caractères");
        
        // Sauvegarder la réponse brute dans un fichier pour débogage
        SaveResponseToFile(response);
        
        // Parser la réponse JSON
        ParseModelsResponse(response);
    }
    else
    {
        Print("Erreur HTTP: ", res);
        Print("Réponse: ", response);
        
        if(res == 403)
            Print("Erreur 403: Clé API invalide");
        else if(res == 404)
            Print("Erreur 404: Endpoint non trouvé");
        else if(res == 429)
            Print("Erreur 429: Trop de requêtes");
    }
}

//+------------------------------------------------------------------+
//| Sauvegarde la réponse dans un fichier                            |
//+------------------------------------------------------------------+
void SaveResponseToFile(string response)
{
    int handle = FileOpen("gemini_models_response.json", FILE_WRITE|FILE_TXT|FILE_ANSI);
    if(handle != INVALID_HANDLE)
    {
        FileWrite(handle, response);
        FileClose(handle);
        Print("Réponse sauvegardée dans: gemini_models_response.json");
    }
}

//+------------------------------------------------------------------+
//| Parse la réponse JSON (version sans librairie externe)           |
//+------------------------------------------------------------------+
void ParseModelsResponse(string json)
{
    Print("\n=== PARSING DES DONNEES ===");
    
    // Chercher le tableau "models"
    int modelsStart = StringFind(json, "\"models\":");
    if(modelsStart == -1)
    {
        Print("ERREUR: 'models' non trouvé dans la réponse");
        return;
    }
    
    // Trouver le début du tableau [
    int arrayStart = StringFind(json, "[", modelsStart);
    if(arrayStart == -1)
    {
        Print("ERREUR: Début du tableau non trouvé");
        return;
    }
    
    // Trouver la fin du tableau ]
    int arrayEnd = FindMatchingBracket(json, arrayStart);
    if(arrayEnd == -1)
    {
        Print("ERREUR: Fin du tableau non trouvée");
        return;
    }
    
    // Extraire le tableau des modèles
    string modelsArray = StringSubstr(json, arrayStart, arrayEnd - arrayStart + 1);
    
    // Compter les modèles
    int modelCount = CountModels(modelsArray);
    Print("Nombre total de modèles: ", modelCount);
    Print("=========================================");
    
    // Extraire chaque modèle
    int displayLimit = ShowAllDetails ? modelCount : MathMin(10, modelCount);
    int currentModel = 0;
    int pos = 0;
    
    while(pos < StringLen(modelsArray) && currentModel < displayLimit)
    {
        // Trouver le début d'un objet modèle {
        int objStart = StringFind(modelsArray, "{", pos);
        if(objStart == -1) break;
        
        // Trouver la fin de l'objet }
        int objEnd = FindMatchingBracket(modelsArray, objStart);
        if(objEnd == -1) break;
        
        // Extraire l'objet modèle
        string modelObj = StringSubstr(modelsArray, objStart, objEnd - objStart + 1);
        
        // Parser l'objet modèle
        ParseModelObject(modelObj, currentModel + 1);
        
        currentModel++;
        pos = objEnd + 1;
    }
    
    if(!ShowAllDetails && modelCount > 10)
        Print("... et ", modelCount - 10, " autres modèles (modifiez 'ShowAllDetails' pour tout afficher)");
    
    // Afficher les statistiques
    DisplayStatistics(json);
    
    // Afficher les modèles recommandés
    ShowRecommendedModels(json);
}

//+------------------------------------------------------------------+
//| Trouve la parenthèse/bracket correspondante                      |
//+------------------------------------------------------------------+
int FindMatchingBracket(string text, int startPos)
{
    int openChar = StringGetCharacter(text, startPos);
    int closeChar;
    
    if(openChar == '{')
        closeChar = '}';
    else if(openChar == '[')
        closeChar = ']';
    else
        return -1;
    
    int depth = 1;
    for(int i = startPos + 1; i < StringLen(text); i++)
    {
        int ch = StringGetCharacter(text, i);
        if(ch == openChar)
            depth++;
        else if(ch == closeChar)
        {
            depth--;
            if(depth == 0)
                return i;
        }
    }
    
    return -1;
}

//+------------------------------------------------------------------+
//| Compte le nombre de modèles dans le tableau                      |
//+------------------------------------------------------------------+
int CountModels(string modelsArray)
{
    int count = 0;
    int pos = 0;
    
    while(pos < StringLen(modelsArray))
    {
        int objStart = StringFind(modelsArray, "{", pos);
        if(objStart == -1) break;
        
        int objEnd = FindMatchingBracket(modelsArray, objStart);
        if(objEnd == -1) break;
        
        count++;
        pos = objEnd + 1;
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Parse un objet modèle individuel                                 |
//+------------------------------------------------------------------+
void ParseModelObject(string modelObj, int index)
{
    Print("Modèle ", index, ":");
    
    // Extraire le nom complet
    string name = ExtractJsonString(modelObj, "name");
    if(name != "")
    {
        Print("  Nom complet: ", name);
        
        // Extraire le nom court
        int slashPos = StringFind(name, "/");
        if(slashPos != -1)
            Print("  Nom court: ", StringSubstr(name, slashPos + 1));
    }
    
    // Extraire le nom affiché
    string displayName = ExtractJsonString(modelObj, "displayName");
    if(displayName != "")
        Print("  Nom affiché: ", displayName);
    
    // Extraire la description
    string description = ExtractJsonString(modelObj, "description");
    if(description != "")
    {
        if(StringLen(description) > 100)
            description = StringSubstr(description, 0, 100) + "...";
        Print("  Description: ", description);
    }
    
    // Extraire les limites de tokens
    int inputTokenLimit = ExtractJsonInt(modelObj, "inputTokenLimit");
    if(inputTokenLimit > 0)
        Print("  Input Token Limit: ", FormatNumber(inputTokenLimit));
    
    int outputTokenLimit = ExtractJsonInt(modelObj, "outputTokenLimit");
    if(outputTokenLimit > 0)
        Print("  Output Token Limit: ", FormatNumber(outputTokenLimit));
    
    // Extraire les méthodes supportées
    string methods = ExtractJsonArray(modelObj, "supportedGenerationMethods");
    if(methods != "")
        Print("  Méthodes supportées: ", methods);
    
    // Extraire les paramètres optionnels
    double temperature = ExtractJsonDouble(modelObj, "temperature");
    if(temperature > 0)
        Print("  Temperature: ", DoubleToString(temperature, 2));
    
    double topP = ExtractJsonDouble(modelObj, "topP");
    if(topP > 0)
        Print("  Top P: ", DoubleToString(topP, 2));
    
    int topK = ExtractJsonInt(modelObj, "topK");
    if(topK > 0)
        Print("  Top K: ", topK);
    
    bool thinking = ExtractJsonBool(modelObj, "thinking");
    Print("  Thinking supporté: ", thinking ? "✓ Oui" : "✗ Non");
    
    Print("-----------------------------------------");
}

//+------------------------------------------------------------------+
//| Extrait une valeur string d'un objet JSON                        |
//+------------------------------------------------------------------+
string ExtractJsonString(string json, string key)
{
    string searchKey = "\"" + key + "\"";
    int keyPos = StringFind(json, searchKey);
    if(keyPos == -1) return "";
    
    int colonPos = StringFind(json, ":", keyPos);
    if(colonPos == -1) return "";
    
    int quotePos = StringFind(json, "\"", colonPos);
    if(quotePos == -1) return "";
    
    int endQuotePos = StringFind(json, "\"", quotePos + 1);
    if(endQuotePos == -1) return "";
    
    return StringSubstr(json, quotePos + 1, endQuotePos - quotePos - 1);
}

//+------------------------------------------------------------------+
//| Extrait une valeur integer d'un objet JSON                       |
//+------------------------------------------------------------------+
int ExtractJsonInt(string json, string key)
{
    string searchKey = "\"" + key + "\"";
    int keyPos = StringFind(json, searchKey);
    if(keyPos == -1) return 0;
    
    int colonPos = StringFind(json, ":", keyPos);
    if(colonPos == -1) return 0;
    
    int startPos = colonPos + 1;
    while(startPos < StringLen(json) && (StringGetCharacter(json, startPos) == ' ' || 
          StringGetCharacter(json, startPos) == '\t' || StringGetCharacter(json, startPos) == '\n'))
        startPos++;
    
    string numStr = "";
    while(startPos < StringLen(json))
    {
        int ch = StringGetCharacter(json, startPos);
        if(ch >= '0' && ch <= '9')
            numStr += CharToString((uchar)ch);
        else if(ch == ',' || ch == '}' || ch == ']')
            break;
        else if(ch == '.' || ch == '-')
            numStr += CharToString((uchar)ch);
        else
            break;
        startPos++;
    }
    
    return (numStr != "") ? (int)StringToInteger(numStr) : 0;
}

//+------------------------------------------------------------------+
//| Extrait une valeur double d'un objet JSON                        |
//+------------------------------------------------------------------+
double ExtractJsonDouble(string json, string key)
{
    string searchKey = "\"" + key + "\"";
    int keyPos = StringFind(json, searchKey);
    if(keyPos == -1) return 0.0;
    
    int colonPos = StringFind(json, ":", keyPos);
    if(colonPos == -1) return 0.0;
    
    int startPos = colonPos + 1;
    while(startPos < StringLen(json) && (StringGetCharacter(json, startPos) == ' ' || 
          StringGetCharacter(json, startPos) == '\t' || StringGetCharacter(json, startPos) == '\n'))
        startPos++;
    
    string numStr = "";
    while(startPos < StringLen(json))
    {
        int ch = StringGetCharacter(json, startPos);
        if((ch >= '0' && ch <= '9') || ch == '.' || ch == '-')
            numStr += CharToString((uchar)ch);
        else if(ch == ',' || ch == '}' || ch == ']')
            break;
        else
            break;
        startPos++;
    }
    
    return (numStr != "") ? StringToDouble(numStr) : 0.0;
}

//+------------------------------------------------------------------+
//| Extrait une valeur boolean d'un objet JSON                       |
//+------------------------------------------------------------------+
bool ExtractJsonBool(string json, string key)
{
    string searchKey = "\"" + key + "\"";
    int keyPos = StringFind(json, searchKey);
    if(keyPos == -1) return false;
    
    int colonPos = StringFind(json, ":", keyPos);
    if(colonPos == -1) return false;
    
    int startPos = colonPos + 1;
    while(startPos < StringLen(json) && (StringGetCharacter(json, startPos) == ' ' || 
          StringGetCharacter(json, startPos) == '\t' || StringGetCharacter(json, startPos) == '\n'))
        startPos++;
    
    // Vérifier "true" ou "false"
    if(StringSubstr(json, startPos, 4) == "true")
        return true;
    else if(StringSubstr(json, startPos, 5) == "false")
        return false;
    
    return false;
}

//+------------------------------------------------------------------+
//| Extrait un tableau JSON                                         |
//+------------------------------------------------------------------+
string ExtractJsonArray(string json, string key)
{
    string searchKey = "\"" + key + "\"";
    int keyPos = StringFind(json, searchKey);
    if(keyPos == -1) return "";
    
    int colonPos = StringFind(json, ":", keyPos);
    if(colonPos == -1) return "";
    
    int arrayStart = StringFind(json, "[", colonPos);
    if(arrayStart == -1) return "";
    
    int arrayEnd = FindMatchingBracket(json, arrayStart);
    if(arrayEnd == -1) return "";
    
    string arrayContent = StringSubstr(json, arrayStart + 1, arrayEnd - arrayStart - 1);
    
    // Nettoyer le tableau pour l'affichage
    StringReplace(arrayContent, "\"", "");
    StringReplace(arrayContent, "\n", "");
    StringReplace(arrayContent, "\r", "");
    
    return arrayContent;
}

//+------------------------------------------------------------------+
//| Formate les grands nombres                                       |
//+------------------------------------------------------------------+
string FormatNumber(int number)
{
    if(number < 1000)
        return IntegerToString(number);
    
    string result = "";
    int temp = number;
    int count = 0;
    
    while(temp > 0)
    {
        if(count > 0 && count % 3 == 0)
            result = "," + result;
        result = IntegerToString(temp % 10) + result;
        temp /= 10;
        count++;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Affiche les statistiques globales                                |
//+------------------------------------------------------------------+
void DisplayStatistics(string json)
{
    Print("\n=== STATISTIQUES GLOBALES ===");
    
    // Compter les modèles par type
    int textModels = 0;
    int embeddingModels = 0;
    
    int modelsStart = StringFind(json, "\"models\":");
    if(modelsStart == -1) return;
    
    int arrayStart = StringFind(json, "[", modelsStart);
    if(arrayStart == -1) return;
    
    int arrayEnd = FindMatchingBracket(json, arrayStart);
    if(arrayEnd == -1) return;
    
    string modelsArray = StringSubstr(json, arrayStart, arrayEnd - arrayStart + 1);
    
    int pos = 0;
    while(pos < StringLen(modelsArray))
    {
        int objStart = StringFind(modelsArray, "{", pos);
        if(objStart == -1) break;
        
        int objEnd = FindMatchingBracket(modelsArray, objStart);
        if(objEnd == -1) break;
        
        string modelObj = StringSubstr(modelsArray, objStart, objEnd - objStart + 1);
        
        string methods = ExtractJsonArray(modelObj, "supportedGenerationMethods");
        if(StringFind(methods, "generateContent") != -1)
            textModels++;
        if(StringFind(methods, "embedContent") != -1)
            embeddingModels++;
        
        pos = objEnd + 1;
    }
    
    Print("Modèles de génération de texte: ", textModels);
    Print("Modèles d'embedding: ", embeddingModels);
    
    // Pagination
    string nextPageToken = ExtractJsonString(json, "nextPageToken");
    if(nextPageToken != "")
        Print("⚠ Note: D'autres modèles sont disponibles (pagination)");
}

//+------------------------------------------------------------------+
//| Affiche les modèles recommandés                                  |
//+------------------------------------------------------------------+
void ShowRecommendedModels(string json)
{
    Print("\n=== MODÈLES RECOMMANDÉS ===");
    
    // Chercher les modèles populaires
    string popularModels[] = {
        "gemini-2.5-flash",
        "gemini-2.5-pro",
        "gemini-2.0-flash",
        "gemini-2.0-flash-lite",
        "gemini-embedding-2"
    };
    
    for(int i = 0; i < ArraySize(popularModels); i++)
    {
        int pos = StringFind(json, popularModels[i]);
        if(pos != -1)
        {
            Print(popularModels[i]);
            
            // Essayer de trouver le displayName à proximité
            int searchStart = (pos > 500) ? pos - 500 : 0;
            int searchEnd = pos + 500;
            if(searchEnd > StringLen(json)) searchEnd = StringLen(json);
            
            string searchArea = StringSubstr(json, searchStart, searchEnd - searchStart);
            string displayName = ExtractJsonString(searchArea, "displayName");
            
            if(displayName != "")
                Print("  → ", displayName);
        }
    }
}

//+------------------------------------------------------------------+
//| NOTE IMPORTANTE:                                                  |
//| 1. Avant d'utiliser, allez dans Outils -> Options -> Experts     |
//| 2. Cochez "Autoriser les requêtes WebRequest"                     |
//| 3. Ajoutez l'URL: https://generativelanguage.googleapis.com/*    |
//| 4. Redémarrez MetaTrader 5                                       |
//+------------------------------------------------------------------+
