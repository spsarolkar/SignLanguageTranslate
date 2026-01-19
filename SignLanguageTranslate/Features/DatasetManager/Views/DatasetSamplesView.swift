import SwiftUI
import SwiftData

struct DatasetSamplesView: View {
    let dataset: Dataset
    
    @Query private var videos: [VideoSample]
    
    init(dataset: Dataset) {
        self.dataset = dataset
        // Filter videos by dataset name
        let name = dataset.name
        _videos = Query(
            filter: #Predicate<VideoSample> { video in
                video.datasetName == name
            },
            sort: \VideoSample.originalFilename
        )
    }
    
    var body: some View {
        List {
            Section {
                if videos.isEmpty {
                    ContentUnavailableView(
                        "No Samples Found",
                        systemImage: "video.slash",
                        description: Text("Ingest the dataset to populate video samples.")
                    )
                } else {
                    ForEach(videos) { video in
                        NavigationLink {
                            FeatureExtractionView(video: video)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(video.fileName)
                                    .fontWeight(.medium)
                                HStack {
                                    Text(video.formattedDuration)
                                    Spacer()
                                    if !video.featureSets.isEmpty {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("\(videos.count) Videos")
            }
        }
        .navigationTitle("Samples: \(dataset.name)")
    }
}
