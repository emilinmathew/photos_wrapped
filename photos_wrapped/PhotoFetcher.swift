//
//  PhotoFetcher.swift
//  photos_wrapped
//
//  Created by Emi Mathew on 12/26/24.
//

import Photos
import SwiftUI
import Vision
import CoreML
import PhotosUI
import UIKit
import CoreLocation


struct ClusterResponse: Decodable {
    let clusters: [Int]?
    let common_face_images: [String]?
    
    enum CodingKeys: String, CodingKey {
        case clusters
        case common_face_images
    }
}


class PhotoFetcher: ObservableObject {
    init() {
        checkAuthorizationStatus()
    }
    
    func checkAuthorizationStatus() {
        let status = PHPhotoLibrary.authorizationStatus()
        DispatchQueue.main.async {
            self.isAuthorized = status == .authorized
            if self.isAuthorized {
                self.fetchPhotos()
            }
        }
    }
    
    @Published var isAuthorized = false
    @Published var photoCount = 0
    @Published var photos: [PHAsset] = []
    @Published var thumbnails: [UIImage] = []
    
    
    // Most Photographed Day
    @Published var mostPhotographedDay: String = ""
    @Published var mostActivePhotos: [UIImage] = []
    @Published var mostActiveDate: Date?
    @Published var mostActiveFavorites: [UIImage] = [] // to show favorites for the carousel
    
    // Most Common Face
    @Published var faceCounts: [String: Int] = [:] // Dictionary to count occurrences of each face
    @Published var mostCommonFaceIdentifier: String? = nil
    @Published var mostCommonFaces: [(identifier: String, image: UIImage?)] = []
    //    @Published var mostCommonFaces: [UIImage] = []
    
    @Published var mostCommonFaceCount: Int = 0
    var allFaceImages: [(identifier: String, images: [UIImage])] = []
    
    // Most Common Subject
    @Published var subjectCounts: [String: Int] = [:]
    @Published var topSubjects: [(subject: String, count: Int)] = []
    @Published var isAnalyzingSubjects = false
    @Published var subjectAnalysisProgress: Float = 0.0
    var assignedImages: Set<UIImage> = []
    
    @Published var subjectImages: [String: [UIImage]] = [:]  // Subject -> Array of sample images
    
    
    // Location Analysis
    @Published var placesCarousel: [(place: String, photos: [UIImage])] = []
    
    
    func requestPhotoAccess() {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                self.isAuthorized = status == .authorized
                if self.isAuthorized {
                    self.fetchPhotos()
                }
            }
        }
    }
    
    func fetchPhotos() {
        let fetchOptions = PHFetchOptions()
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: 2024, month: 12, day: 31))!
        
        fetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        
        // Get all photos from 2024
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        // Convert to array and randomly select 40
        var allPhotosArray: [PHAsset] = []
        allPhotos.enumerateObjects { (asset, _, _) in
            allPhotosArray.append(asset)
        }
        
        DispatchQueue.main.async {
            self.photoCount = allPhotos.count
            self.photos.removeAll()
            allPhotosArray.forEach { asset in
                self.photos.append(asset)
            }
            self.analyzePhotos()
            self.loadThumbnails()
        }
    }
    
    
    
    func loadThumbnails() {
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        
        thumbnails.removeAll() // Clear existing thumbnails first
        
        for asset in photos {
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 100, height: 100),
                contentMode: .aspectFill,
                options: requestOptions
            ) { image, _ in
                if let image = image {
                    DispatchQueue.main.async {
                        self.thumbnails.append(image)
                    }
                }
            }
        }
    }
    
    
    func analyzePhotos() {
        var photosPerDay: [Date: [PHAsset]] = [:]  // Changed to store assets per day
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        
        // Group photos by day
        for photo in photos {
            if let date = photo.creationDate {
                // Remove time component to group by day
                let calendar = Calendar.current
                let dateOnly = calendar.startOfDay(for: date)
                if photosPerDay[dateOnly] == nil {
                    photosPerDay[dateOnly] = []
                }
                photosPerDay[dateOnly]?.append(photo)
            }
        }
        
        // Find day with most photos
        if let maxDay = photosPerDay.max(by: { $0.value.count < $1.value.count }) {
            mostActiveDate = maxDay.key
            mostPhotographedDay = dateFormatter.string(from: maxDay.key) + " (\(maxDay.value.count) photos)"
            loadMostActivePhotos(assets: maxDay.value)
        }
    }
    
    private func loadMostActivePhotos(assets: [PHAsset]) {
        print("Loading most active photos...")
        print("Total assets: \(assets.count)")
        
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat  // Only deliver high quality
        requestOptions.isSynchronous = false
        requestOptions.version = .current  // Only get the current version
        
        mostActiveFavorites.removeAll()
        
        if assets.count < 10 {
            // If less than 10 photos total, show all of them
            let photosToShow = assets
            
            for asset in photosToShow {
                imageManager.requestImage(
                    for: asset,
                    targetSize: CGSize(width: 300, height: 300),
                    contentMode: .aspectFill,
                    options: requestOptions
                ) { image, info in
                    // Only add the final image version
                    if let image = image, info?[PHImageResultIsDegradedKey] as? Bool == false {
                        DispatchQueue.main.async {
                            self.mostActiveFavorites.append(image)
                        }
                    }
                }
            }
        } else {
            // Filter for favorite photos and limit to 10
            let favorites = assets.filter { asset in
                asset.isFavorite
            }.shuffled().prefix(10)
            
            // Calculate how many regular photos we need
            let favoritesCount = favorites.count
            let regularPhotosNeeded = 10 - favoritesCount
            
            // Get regular photos (excluding favorites)
            let regularPhotos = assets.filter { asset in
                !asset.isFavorite
            }.prefix(regularPhotosNeeded)
            
            // Combine favorites and regular photos
            let photosToShow = Array(favorites) + Array(regularPhotos)
            
            for asset in photosToShow {
                imageManager.requestImage(
                    for: asset,
                    targetSize: CGSize(width: 300, height: 300),
                    contentMode: .aspectFill,
                    options: requestOptions
                ) { image, info in
                    // Only add the final image version
                    if let image = image, info?[PHImageResultIsDegradedKey] as? Bool == false {
                        DispatchQueue.main.async {
                            self.mostActiveFavorites.append(image)
                        }
                    }
                }
            }
        }
    }
    
    
    // Find the most common subject throughout 2024
    func analyzeSubjects() {
        isAnalyzingSubjects = true
        subjectAnalysisProgress = 0.0
        subjectCounts.removeAll()
        
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        
        let totalPhotos = photos.count
        var processedCount = 0
        
        
        for (_, asset) in photos.enumerated() {
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 500, height: 500),
                contentMode: .aspectFit,
                options: requestOptions
            ) { [weak self] image, _ in
                guard let self = self, let image = image else { return }
                
                self.processImage(image) { subjectsWithConfidence in
                    DispatchQueue.main.async {
                        // Sort subjects by confidence and take the highest one
                        if let bestSubject = subjectsWithConfidence.sorted(by: { $0.confidence > $1.confidence }).first {
                            let subject = bestSubject.subject
                            
                            // Only add this image to the subject if it hasn't been assigned yet
                            if !self.assignedImages.contains(image) {
                                self.subjectImages[subject, default: []].append(image)
                                self.assignedImages.insert(image) // Mark this image as assigned
                                
                                // Update counts for each detected subject
                                self.subjectCounts[subject, default: 0] += 1
                            }
                        }
                        
                        // Update progress
                        processedCount += 1
                        self.subjectAnalysisProgress = Float(processedCount) / Float(totalPhotos)
                        
                        // Finalize when all photos are processed
                        if processedCount == totalPhotos {
                            self.finalizeSubjectAnalysis()
                        }
                    }
                }
            }
        }
        DispatchQueue.main.async {
            self.isAnalyzingSubjects = false
        }
    }
    
    private func processImage(_ image: UIImage, completion: @escaping ([(subject: String, confidence: Float)]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }
        
        // Create requests for different types of analysis
        let requests = [
            VNClassifyImageRequest(), // General scene classification
            VNDetectFaceRectanglesRequest(), // Face detection
            VNRecognizeAnimalsRequest() // Animal detection
        ]
        
        let handler = VNImageRequestHandler(cgImage: cgImage)
        
        do {
            try handler.perform(requests)
            
            var detectedSubjects: [(subject: String, confidence: Float)] = []
            var faceCount = 0 // Declare faceCount here
            
            // Dictionary to count occurrences of each face (using bounding box as identifier)
            var faceCounts: [String: Int] = [:]
            
            // Process classification results
            if let classificationResults = requests[0].results as? [VNClassificationObservation] {
                for result in classificationResults.prefix(2) where result.confidence > 0.7 {
                    let subject = result.identifier
                        .split(separator: ",")
                        .first?
                        .trimmingCharacters(in: .whitespaces)
                        .capitalized
                    
                    if let subject = subject {
                        detectedSubjects.append((subject: subject, confidence: result.confidence))
                    }
                }
            }
            
            // Process face detection results
            if let faceResults = requests[1].results as? [VNFaceObservation] {
                faceCount = faceResults.count
                
                for face in faceResults {
                    // Use bounding box as a unique identifier for counting faces
                    let faceIdentifier = "\(face.boundingBox)" // You might want to use a more robust identifier in a real application
                    faceCounts[faceIdentifier, default: 0] += 1 // Increment count for this face
                    
                    if faceCount > 0 {
                        detectedSubjects.append((subject: "Person", confidence: 0.99)) // High confidence for face detection
                    }
                }
            }
            
            // Process animal detection results
            if let animalResults = requests[2].results as? [VNRecognizedObjectObservation] {
                for result in animalResults where result.confidence > 0.8 {
                    if let label = result.labels.first?.identifier.capitalized {
                        detectedSubjects.append((subject: label, confidence: result.confidence))
                    }
                }
            }
            
            // Logic for tiebreaking between "Person" and "People"
            if faceCount > 1 && detectedSubjects.contains(where: { $0.subject == "People" }) {
                completion([(subject: "People", confidence: 1.0)]) // Assign with high confidence
            } else {
                completion(detectedSubjects)
            }
            
            // Determine and store the most common face based on counts
            if let mostCommonFace = faceCounts.max(by: { $0.value < $1.value }) {
                mostCommonFaceIdentifier = mostCommonFace.key
                mostCommonFaceCount = mostCommonFace.value
                
                print("Most common face identifier: \(mostCommonFace.key) with count \(mostCommonFace.value)")
                // Here you can also store or process the actual image associated with this identifier if needed.
            }
            
        } catch {
            print("Image analysis failed: \(error)")
            completion([])
        }
    }
    
    
    
    private func finalizeSubjectAnalysis() {
        // Create a dictionary to store images by subject
        var imagesBySubject: [String: [UIImage]] = [:]
        
        // Organize images by their most confident subject
        for (subject, images) in subjectImages {
            // Only add images if they haven't been assigned already
            for image in images {
                // Check if the image is already assigned to another subject
                if !imagesBySubject.values.contains(where: { $0.contains(image) }) {
                    imagesBySubject[subject, default: []].append(image)
                }
            }
        }
        
        // Get top subjects with their sample images
        topSubjects = subjectCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { subject, count in
                // Convert to expected tuple type (subject: String, count: Int)
                (subject: subject, count: count)
            }
    }
    
    
    func analyzeCommonFaces() {
        // Ensure 'photos' is not empty
        guard !photos.isEmpty else {
            print("No photos available.")
            return
        }
        
        // Create an array to hold the images
        var images: [UIImage] = []
        
        // Use a dispatch group to wait for all images to be fetched
        let dispatchGroup = DispatchGroup()
        
        // Fetch images asynchronously
        for asset in photos {
            dispatchGroup.enter() // Enter the dispatch group for each asset
            
            let options = PHImageRequestOptions()
            options.isSynchronous = false // Make sure the request is asynchronous
            options.deliveryMode = .highQualityFormat
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 300, height: 300),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                if let image = image {
                    images.append(image) // Add the fetched image to the array
                } else {
                    print("Failed to fetch image for asset: \(asset)")
                }
                dispatchGroup.leave() // Leave the dispatch group after the image is fetched
            }
        }
        
        // Wait for all image fetching tasks to finish
        dispatchGroup.notify(queue: .main) {
            // Debug: Check the number of images fetched
            print("Fetched \(images.count) images for analysis.")
            
            // Send images to the server only after all images are fetched
            self.sendImagesToServer(images: images) { clusters, commonFaceImages, errorMessage in
                // Debugging: Print the clusters and common face images to the console
                if clusters.allSatisfy({ $0 == -1 }) {
                    print("Warning: All clusters are -1. There may be an issue with the clustering process.")
                }
                
                // Check if there's an error message and print it
                if let errorMessage = errorMessage {
                    print("Error: \(errorMessage)")
                }
                
                // Make sure that common face images are being returned and are not empty
                if commonFaceImages.isEmpty {
                    print("No common faces found!")
                } else {
                    print("Found \(commonFaceImages.count) common face images.")
                }
                
                // Update the UI on the main thread
                DispatchQueue.main.async {
                    // Convert base64 image strings into UIImages
                    let images: [UIImage] = commonFaceImages // No need to map or decode
                    
                    
                    // Update the most common faces array with new images
                    self.mostCommonFaces = images.enumerated().map { (index, image) in
                        let identifier = UUID().uuidString  // Generate a unique identifier for each face
                        return (identifier: identifier, image: image)
                    }
                    
                    self.isAnalyzingSubjects = false
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    
    func sendImagesToServer(images: [UIImage], completion: @escaping ([Int], [UIImage], String?) -> Void) {
        // I've deleted my url - Input yours
        guard let url = URL(string: "http://") else {
            completion([], [], "Invalid URL.")
            return
        }
        let urlCache = URLCache.shared
        urlCache.removeAllCachedResponses()
        
        
        // Perform image resizing and base64 encoding on a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            let resizedImages = images.map { image in
                self.resizeImage(image, targetSize: CGSize(width: 160, height: 160))
            }
            let imageData = resizedImages.compactMap { $0.jpegData(compressionQuality: 0.6)?.base64EncodedString() }
            let payload = ["images": imageData]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            } catch {
                print("Error serializing JSON: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion([], [], error.localizedDescription)
                }
                return
            }
            
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 120
            
            let session = URLSession(configuration: configuration)
            
            session.dataTask(with: request) { data, response, error in
                guard let data = data, error == nil else {
                    print("Error: \(error?.localizedDescription ?? "Unknown error")")
                    DispatchQueue.main.async {
                        completion([], [], error?.localizedDescription)
                    }
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    print("Server returned status code: \(httpResponse.statusCode)")
                    DispatchQueue.main.async {
                        completion([], [], "Server returned status code \(httpResponse.statusCode)")
                    }
                    return
                }
                
                do {
                    // Decode the response to get the clusters and common_face_images
                    let result = try JSONDecoder().decode(ClusterResponse.self, from: data)
                    DispatchQueue.main.async {
                        let clusters = result.clusters ?? []
                        var decodedImages: [UIImage] = []
                        
                        // Decode the base64 strings into images
                        if let base64ImageStrings = result.common_face_images {
                            decodedImages = base64ImageStrings.compactMap { self.decodeBase64ToImage(base64String: $0) }
                        }
                        
                        // Return clusters and the decoded images
                        completion(clusters, decodedImages, nil)
                    }
                } catch let decodingError as DecodingError {
                    print("Decoding error: \(decodingError.localizedDescription)")
                    DispatchQueue.main.async {
                        completion([], [], decodingError.localizedDescription)
                    }
                } catch {
                    print("Error decoding response: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion([], [], error.localizedDescription)
                    }
                }
            }.resume()
        }
    }
    
    func decodeBase64ToImage(base64String: String) -> UIImage? {
        if let imageData = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) {
            return UIImage(data: imageData)
        }
        return nil
    }
    
    struct ClusterResponse: Codable {
        var clusters: [Int]?
        var common_face_images: [String]?
    }
    
    
    
    func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        
        let newSize = CGSize(width: size.width * widthRatio, height: size.height * heightRatio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // Method to fetch image metadata including coordinates
    func getImageMetadata(asset: PHAsset, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        // Fetch the location directly from the asset
        if let location = asset.location {
            // If the asset has location data, use it directly
            completion(location.coordinate)
        } else {
            print("No location found for asset: \(asset)")
            completion(nil)
        }
    }
    
    // Reverse geocoding method with throttling mechanism
    func reverseGeocode(coordinate: CLLocationCoordinate2D, completion: @escaping (String?) -> Void) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        // Throttling: Add a delay or a queue mechanism if required
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                guard error == nil, let placemark = placemarks?.first else {
                    completion(nil)
                    return
                }
                
                let locationName = placemark.locality ?? placemark.country ?? "Unknown location"
                completion(locationName)
            }
        }
    }
    
    
    
    @State private var imagesLoaded = false
    @State private var placesWithImages: [(place: String, photos: [UIImage])] = []
    
    func loadCarouselOfPlaces(completion: @escaping (Result<[(place: String, photos: [UIImage])], Error>) -> Void) {
        print("Started loading carousel of places")
        
        var locationPhotos: [String: [PHAsset]] = [:]
        let dispatchGroup = DispatchGroup()
        
        // Collect photos for each place
        for asset in photos {
            dispatchGroup.enter()
            
            print("Fetching metadata for asset: \(asset)")
            
            getImageMetadata(asset: asset) { coordinate in
                guard let coordinate = coordinate else {
                    print("No coordinate found for asset: \(asset)")
                    dispatchGroup.leave()
                    return
                }
                
                self.reverseGeocode(coordinate: coordinate) { placeName in
                    guard let placeName = placeName else {
                        print("Failed to reverse geocode coordinate: \(coordinate)")
                        dispatchGroup.leave()
                        return
                    }
                    
                    print("Found place: \(placeName)")
                    
                    DispatchQueue.main.async {
                        locationPhotos[placeName, default: []].append(asset)
                        dispatchGroup.leave()
                    }
                }
            }
        }
        
        // Once all metadata is fetched
        dispatchGroup.notify(queue: .main) {
            print("Finished loading all places")
            
            var placesCarousel: [(place: String, photos: [UIImage])] = []
            
            // Load images for each place
            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.deliveryMode = .highQualityFormat
            
            for (place, assets) in locationPhotos {
                var images: [UIImage] = []
                let selectedAssets = assets.prefix(5) // Select up to 5 photos
                
                let imageDispatchGroup = DispatchGroup()
                
                for asset in selectedAssets {
                    imageDispatchGroup.enter()
                    
                    imageManager.requestImage(
                        for: asset,
                        targetSize: CGSize(width: 300, height: 300),
                        contentMode: .aspectFill,
                        options: requestOptions
                    ) { image, _ in
                        if let image = image {
                            images.append(image)
                            print("Image loaded for \(place): \(images.count) images now.")
                        }
                        imageDispatchGroup.leave()
                    }
                }
                
                // Once all images for this place are loaded
                imageDispatchGroup.notify(queue: .main) {
                    if !images.isEmpty {
                        placesCarousel.append((place: place, photos: images))
                        
                        // Check if all places have been processed
                        if placesCarousel.count == locationPhotos.count {
                            self.placesWithImages = placesCarousel
                            self.imagesLoaded = true
                            print("All images loaded: \(placesCarousel)")
                            completion(.success(placesCarousel))  // Notify the caller with the data
                        }
                    } else {
                        print("No images found for \(place)")
                    }
                }
            }
        }
    }
}

