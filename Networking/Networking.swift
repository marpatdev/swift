import Cocoa

struct Response: Codable {
    struct Contents: Codable {
        var text: String
        var translated: String
        var translation: String
    }
    
    struct Success: Codable {
        var total: Int
    }
    
    var contents: Contents
    var success: Success
}

enum RequestType: String {
    case POST
    case GET
    case DELETE
    case UPLOAD
}

struct Request<Model: Codable> {
    var urlComponents: URLComponents? = nil
    let maxRetries: Int
    
    func request(requestType: RequestType) -> URLRequest? {
        guard let urlComponents = urlComponents else {
            return nil
        }
        
        guard let url = urlComponents.url else {
            return nil
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = requestType.rawValue
        urlRequest.httpBody = urlComponents.percentEncodedQuery?.data(using: String.Encoding.utf8)
        
        return urlRequest
    }
    
    init(endpoint: String,
         parameters: [String: String]? = nil,
         maxRetries: Int = 0) {
        self.urlComponents = URLComponents(string: endpoint)
        
        self.urlComponents?.queryItems = parameters?.map { (key, value) in
            return URLQueryItem(name: key, value: value)
        }
        
        self.maxRetries = min(maxRetries, 10)
    }
}

enum NetworkingStatusCode: Int {
    // Informational
    case `continue` = 100
    case switchingProtocols = 101
    case processing = 102
    
    var isInformational: Bool {
        return rawValue / 100 == 1
    }
    
    // Success
    case ok = 200
    case created = 201
    case accepted = 202
    case nonAuthoritativeInformation = 203
    case noContent = 204
    case resetContent = 205
    case partialContent = 206
    case multiStatus = 207
    case alreadyReported = 208
    case IMUsed = 209
    
    var isSuccessfull: Bool {
        return rawValue / 100 == 2
    }
    
    // Redirection
    case multipleChoices = 300
    case movedPermanently = 301
    case found = 302
    case seeOther = 303
    case notModified = 304
    case useProxy = 305
    case switchProxy = 306
    case temporaryRedirect = 307
    case permanentRedirect = 308
    
    var isRedirection: Bool {
        return rawValue / 100 == 3
    }
    
    // Client error
    
    case badRequest = 400
    case unauthorised = 401
    case paymentRequired = 402
    case forbidden = 403
    case notFound = 404
    case methodNotAllowed = 405
    case notAcceptable = 406
    case proxyAuthenticationRequired = 407
    case requestTimeout = 408
    case conflict = 409
    case gone = 410
    case lengthRequired = 411
    case preconditionFailed = 412
    case requestEntityTooLarge = 413
    case requestURITooLong = 414
    case unsupportedMediaType = 415
    case requestedRangeNotSatisfiable = 416
    case expectationFailed = 417
    case IamATeapot = 418
    case authenticationTimeout = 419
    case methodFailureSpringFramework = 420
    case misdirectedRequest = 421
    case unprocessableEntity = 422
    case locked = 423
    case failedDependency = 424
    case unorderedCollection = 425
    case upgradeRequired = 426
    case preconditionRequired = 428
    case tooManyRequests = 429
    case requestHeaderFieldsTooLarge = 431
    case noResponseNginx = 444
    case retryWithMicrosoft = 449
    case blockedByWindowsParentalControls = 450
    case unavailableForLegalReasons = 451
    
    // Server error
    case internalServerError = 500
    case notImplemented = 501
    case badGateway = 502
    case serviceUnavailable = 503
    case gatewayTimeout = 504
    case HTTPVersionNotSupported = 505
    case variantAlsoNegotiates = 506
    case insufficientStorage = 507
    case loopDetected = 508
    case bandwidthLimitExceeded = 509
    case notExtended = 510
    case networkAuthenticationRequired = 511
    case connectionTimedOut = 522
    case networkReadTimeoutErrorUnknown = 598
    case networkConnectTimeoutErrorUnknown = 599
    
    var isServerError: Bool {
        return rawValue / 100 == 5
    }
}
struct NetworkingStatusCodeError: Error {
    let code: NetworkingStatusCode
}

extension Error {
    var code: Int {
        return (self as NSError).code
    }
}
    
    
struct Networking {
    enum NetworkinError: Error {
        case incorrectRequest
        case responseWithoutData
    }
    
    static let shared = Networking()
    
    private func perform(urlRequest: URLRequest,
                         retryCount: Int = 0,
                         maxRetries: Int = 0,
                         session: URLSession,
                         success: @escaping (Data?, URLResponse?) -> Void,
                         failure: @escaping (Error) -> Void) {
        let task = session.dataTask(with: urlRequest) { (data, response, error) in
            if let error = error {
                switch error.code {
                case URLError.timedOut.rawValue,
                     URLError.cannotFindHost.rawValue,
                     URLError.cannotConnectToHost.rawValue,
                     URLError.networkConnectionLost.rawValue,
                     URLError.dnsLookupFailed.rawValue where retryCount < maxRetries:
                    self.perform(urlRequest: urlRequest,
                                 retryCount: retryCount + 1,
                                 maxRetries: maxRetries,
                                 session: session,
                                 success: success,
                                 failure: failure)
                default:
                    failure(error)
                }
            } else if let error = self.error(from: response) {
                failure(error)
            } else {
                success(data, response)
            }
        }
        
        task.resume()
    }
    
    private func error(from response: URLResponse?) -> Error? {
        guard let response = response as? HTTPURLResponse else {
            return nil
        }
        
        guard let statusCode = NetworkingStatusCode(rawValue: response.statusCode) else {
            return nil
        }
        
        if statusCode.isSuccessfull {
            return nil
        } else {
            return NetworkingStatusCodeError(code: statusCode)
        }
    }
}

extension Networking {
    func get<Model: Codable>(request: Request<Model>,
                             session: URLSession = URLSession.shared,
                             completion: @escaping ((Result<Model, Error>) -> Void)) -> Void {
        guard let urlRequest = request.request(requestType: .GET) else {
            completion(.failure(NetworkinError.incorrectRequest))
            return
        }
        
        perform(urlRequest: urlRequest,
                maxRetries: request.maxRetries,
                session: session,
                success: { (data, response) in
            if let data = data {
                do {
                    let model = try JSONDecoder().decode(Model.self, from: data)
                    completion(.success(model))
                } catch {
                    completion(.failure(error))
                }
            } else {
                completion(.failure(NetworkinError.responseWithoutData))
            }
        }) { (error) in
            completion(.failure(error))
        }
    }
    
    func post<Model: Codable>(request: Request<Model>,
                              session: URLSession = URLSession.shared,
                              completion: @escaping ((Result<Model, Error>) -> Void)) -> Void {
        guard let urlRequest = request.request(requestType: .POST) else {
            completion(.failure(NetworkinError.incorrectRequest))
            return
        }
        
        perform(urlRequest: urlRequest,
                maxRetries: request.maxRetries,
                session: session,
                success: { (data, response) in
            if let data = data {
                do {
                    let model = try JSONDecoder().decode(Model.self, from: data)
                    completion(.success(model))
                } catch {
                    completion(.failure(error))
                }
            } else {
                completion(.failure(NetworkinError.responseWithoutData))
            }
        }) { (error) in
            completion(.failure(error))
        }
    }
}
