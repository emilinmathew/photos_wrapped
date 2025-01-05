from flask import Flask, request, jsonify
from deepface import DeepFace
from sklearn.cluster import DBSCAN
import numpy as np
import base64
from io import BytesIO
from PIL import Image
import logging
from collections import Counter
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler
from sklearn.metrics.pairwise import cosine_similarity  # Add this import


import sys
print(sys.executable)


def preprocess_embeddings(embeddings):
    # Normalize each embedding to unit length
    embeddings = np.array([e / np.linalg.norm(e) for e in embeddings])
    
    # Apply feature scaling
    scaler = StandardScaler()
    scaled_embeddings = scaler.fit_transform(embeddings)
    
    
    # Determine the valid max components
    max_components = min(len(embeddings), len(embeddings[0]))  # n_samples, n_features
    n_components = min(200, max_components)  # Use 50 or the maximum possible

    pca = PCA(n_components=n_components)
    reduced_embeddings = pca.fit_transform(embeddings)

    logging.info(f"PCA reduced embeddings to {reduced_embeddings.shape[1]} components")

    return reduced_embeddings


app = Flask(__name__)

# Configuration settings
app.config['TIMEOUT'] = 600  # Set timeout to 10 minutes
app.config['MAX_CONTENT_LENGTH'] = 50 * 1024 * 1024  # Set max content length to 50 MB

logging.basicConfig(level=logging.INFO)

def base64_to_image(base64_str):
    try:
        decoded = base64.b64decode(base64_str)
        img = Image.open(BytesIO(decoded))
        return np.array(img)
    except Exception as e:
        logging.error(f"Error converting base64 to image: {str(e)}")
        return None

@app.route('/')
def home():
    return "Hello, Flask!"


@app.route('/cluster', methods=['POST'])
def cluster_faces():
    logging.info("Received request to /cluster endpoint")
    try:
        images = request.json.get("images", [])
        logging.info(f"Received {len(images)} images")
        embeddings = []

        if not images:
            return jsonify({"error": "No images provided"}), 400

        for i, img_data in enumerate(images):
            if not img_data.strip():  # Check if base64 string is not empty
                logging.warning(f"Skipping image {i} due to empty base64 string")
                continue

            img = base64_to_image(img_data)
            if img is not None:
                try:
                    # Attempt to represent the face
                    result = DeepFace.represent(img, model_name="Facenet", enforce_detection=True)
                    embedding = result[0]["embedding"]
                    embeddings.append(list(map(float, embedding)))  # Convert embedding to float list
                except Exception as e:
                    # Skip image if face detection fails
                    continue
            else:
                logging.warning(f"Skipping image {i} due to conversion error")

        if not embeddings:
            return jsonify({"error": "No valid images processed"}), 400
    
        logging.info(f"Processed {len(embeddings)} embeddings.")

        # Step 3: Apply PCA to reduce dimensionality
        new_embeddings = preprocess_embeddings(embeddings)

        # Perform clustering
        clustering = DBSCAN(metric="euclidean", eps=0.4, min_samples=10)
        cluster_labels = clustering.fit_predict(new_embeddings)

        # Convert cluster_labels to a list of integers for compatibility
        cluster_labels = cluster_labels.astype(int).tolist()

        logging.info(f"Clustering with DBSCAN resulted in {len(set(cluster_labels))} clusters.")

        # Identify the most common cluster (mode)
        cluster_counts = Counter(cluster_labels)
        most_common_cluster = cluster_counts.most_common(1)[0][0]  # Get the most common cluster label

        # Find the indices of the images that belong to the most common cluster
        common_face_indices = [i for i, label in enumerate(cluster_labels) if label == most_common_cluster]

        # Retrieve the embeddings and images of the most common face
        common_face_embeddings = [new_embeddings[i] for i in common_face_indices]
        common_face_images = [images[i] for i in common_face_indices]

        logging.info("Clustering completed successfully")
        logging.info(f"Found {len(common_face_images)} common face images")

        # Step 4: Calculate similarity between embeddings and the cluster centroid
        centroid = np.mean(common_face_embeddings, axis=0)

        # Step 5: Calculate confidence for each image (cosine similarity)
        similarities = []
        for i, embedding in enumerate(common_face_embeddings):
            # Cosine similarity between the image embedding and the centroid
            similarity = cosine_similarity([embedding], [centroid])[0][0]
            similarities.append((common_face_images[i], similarity))

        # Step 6: Sort the images by similarity (confidence) and get the top 5
        top_5_images = sorted(similarities, key=lambda x: x[1], reverse=True)[:5]
        logging.info(f"Extracted the top {len(top_5_images)} images for the found face")


        # Step 7: Return the top 5 most confident images
        return jsonify({
            "clusters": cluster_labels,
            "top_5_images": [image for image, _ in top_5_images]
        })

    except Exception as e:
        logging.error(f"Error in cluster_faces: {str(e)}")
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host='0.0.0.0', debug=True, port=5005)
