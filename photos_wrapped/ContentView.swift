//
//  ContentView.swift
//  photos_wrapped
//
//  Created by Emi Mathew on 12/26/24.
//
import SwiftUI
import PhotosUI


struct ImageCarousel: View {
    @State private var selection = 0
    var images: [UIImage] // Assuming you are passing an array of UIImages
    
    var body: some View {
        ZStack {
            TabView(selection: $selection) {
                ForEach(0..<images.count, id: \.self) { index in
                    Image(uiImage: images[index])
                        .resizable()
                        .scaledToFit()
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle())
            
            // Optional: Add page indicators
            HStack {
                Spacer()
                PageIndicator(currentIndex: selection, totalPages: images.count)
                    .padding(.trailing)
            }
        }
        .frame(height: 300) // Set a fixed height for the carousel
    }
}

// A simple Page Indicator view
struct PageIndicator: View {
    var currentIndex: Int
    var totalPages: Int
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.blue : Color.gray)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

struct FaceAnalysisView: View {
    let mostCommonFaces: [(face: UIImage, count: Int)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Most Common Faces")
                .font(.headline)
            
            ForEach(Array(mostCommonFaces.enumerated()), id: \.offset) { index, face in
                HStack {
                    Image(uiImage: face.face)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading) {
                        Text("Person \(index + 1)")
                            .font(.subheadline)
                        Text("\(face.count) appearances")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}


struct SubjectAnalysisView: View {
    @ObservedObject var photoFetcher: PhotoFetcher
    let topSubjects: [(subject: String, count: Int)]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 20) {
                ForEach(topSubjects, id: \.subject) { subject, count in
                    VStack {
                        if let sampleImages = photoFetcher.subjectImages[subject] {
                            TabView {
                                ForEach(sampleImages, id: \.self) { image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 180, height: 180)
                                        .clipped()
                                }
                            }
                            .frame(width: 200, height: 200)
                            .tabViewStyle(PageTabViewStyle())
                            .cornerRadius(10)
                        }
                        
                        Text(subject)
                            .font(.headline)
                        Text("\(count) photos")
                            .font(.subheadline)
                    }
                    .frame(width: 200)
                }
            }
            .padding()
        }
    }
}


struct CarouselView: View {
    let photos: [UIImage]
    
    var body: some View {
        TabView {
            ForEach(0..<photos.count, id: \.self) { index in
                Image(uiImage: photos[index])
                    .resizable()
                    .scaledToFill()
                    .frame(width: 300, height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .padding()
            }
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}


struct ContentView: View {
    // Declare your @StateObject here
    @StateObject private var photoFetcher = PhotoFetcher()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("2024 Photo Wrapped")
                    .font(.largeTitle)
                    .bold()
                
                // Debug Text
                Text("Photos Count: \(photoFetcher.photos.count)")
                Text("Thumbnails Count: \(photoFetcher.thumbnails.count)")
                
                if photoFetcher.isAuthorized {
                    VStack(spacing: 15) {
                        Text("Total Photos: \(photoFetcher.photoCount)")
                            .font(.headline)
                        
                        // Most Active Day and Carousel Section
                        if !photoFetcher.mostPhotographedDay.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Most Active Day: \(photoFetcher.mostPhotographedDay)")
                                    .font(.headline)
                                
                                if !photoFetcher.mostActiveFavorites.isEmpty {
                                    CarouselView(photos: photoFetcher.mostActiveFavorites)
                                        .frame(height: 300)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                        }
                        
                        if photoFetcher.isAnalyzingSubjects {
                            ProgressView("Analyzing subjects...",
                                         value: photoFetcher.subjectAnalysisProgress)
                            .progressViewStyle(.linear)
                        }
                        else if !photoFetcher.topSubjects.isEmpty {
                            SubjectAnalysisView(photoFetcher: photoFetcher,
                                                topSubjects: photoFetcher.topSubjects)
                        } else {
                            Button("Analyze Subjects") {
                                photoFetcher.analyzeSubjects()
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        
                        // Common Faces Section
                        analyzeCommonFacesSection
                            .padding()
                        
                        // Places Section
                        placesCarouselSection
                            .padding()
                        
                        // Thumbnails Section
                        thumbnailsSection
                            .padding()
                    }
                    .padding() // Add padding to the main VStack for better layout
                } else {
                    Button(action: {
                        photoFetcher.requestPhotoAccess()
                    }) {
                        Text("Allow Photo Access")
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
            .padding() // Add padding to the main ScrollView for better layout
        }
    }
    
    
    private var analyzeCommonFacesSection: some View {
        VStack {
            Text("Most Common Faces:")
                .font(.headline)
                .padding(.top)
            
            if !photoFetcher.mostCommonFaces.isEmpty {
                // Horizontal ScrollView for carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        // Loop through mostCommonFaces and display images
                        ForEach(photoFetcher.mostCommonFaces, id: \.identifier) { face in
                            VStack {
                                if let image = face.image {  // Unwrap the optional image
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 150, height: 150)
                                        .cornerRadius(10)
                                        .clipped()
                                        .padding()
                                } else {
                                    Text("No Image Available")
                                        .foregroundColor(.gray)
                                        .frame(width: 150, height: 150)  // Ensure consistent size
                                        .padding()
                                        .background(Color.gray.opacity(0.3))
                                        .cornerRadius(10)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)  // Add padding around the ScrollView
            } else {
                // Show button to trigger common face analysis if no faces found
                Button("Analyze Common Faces") {
                    photoFetcher.analyzeCommonFaces()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()  // Add padding around the entire VStack
    }
    
    
    
    
    // Thumbnails Section
    private var thumbnailsSection: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
            ForEach(photoFetcher.thumbnails, id: \.self) { image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 5)
            }
        }
        .padding() // Padding around the grid
    }
    
    @State private var placesWithImages: [(place: String, photos: [UIImage])] = []
    @State private var isLoading = false

    private var placesCarouselSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Places Visited in 2024")
                .font(.headline)
                .padding(.top)
            
            if placesWithImages.isEmpty {  // Check if placesWithImages is empty
                VStack {
                    Text("No locations analyzed yet.")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                    
                    Button("Analyze Locations") {
                        print("Button pressed: Starting location analysis")
                        
                        photoFetcher.loadCarouselOfPlaces { result in
                            switch result {
                            case .success(let loadedPlaces):
                                placesWithImages = loadedPlaces  // Update state with loaded data
                            case .failure(let error):
                                print("Error loading places: \(error)")
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 30) {  // Increase the space between items
                        ForEach(placesWithImages, id: \.place) { placeData in
                            VStack(spacing: 12) {  // Increase spacing within the place item box

                                Text(placeData.place)
                                    .font(.subheadline)
                                    .bold()
                                    .padding(.bottom, 5)

                                if !placeData.photos.isEmpty {
                                    CarouselView(photos: placeData.photos)
                                        .frame(width: 300, height: 300)
                                        .padding([.leading, .trailing], 10)
                                        .cornerRadius(8)  // Add rounded corners to the images
                                } else {
                                    Text("Loading...")
                                        .frame(height: 250)
                                        .padding([.leading, .trailing], 10)
                                        .cornerRadius(8)
                                }
                            }
                            .padding(15)  // Add padding around each place item box
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(15)  // Add rounded corners for each place item box
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding()
    }

    
    
    
    
}
