import tensorflow as tf
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import functools
import csv
import time
from tensorflow.keras.callbacks import TensorBoard


LABEL_COLUMN = 'is_cheat'

# "I:\csgoserver\steamcmd\steamapps\common\Counter-Strike Global Offensive Beta - Dedicated Server\csgo\addons\sourcemod\训练数据.csv"
train_file_path = [
    r"I:\csgoserver\steamcmd\steamapps\common\Counter-Strike Global Offensive Beta - Dedicated Server\csgo\addons\sourcemod\训练数据.csv"]
test_file_path = [
    r"I:\csgoserver\steamcmd\steamapps\common\Counter-Strike Global Offensive Beta - Dedicated Server\csgo\addons\sourcemod\测试数据1.csv"]
csv_data = []
csv_data_x = []
csv_data_y = []
csv_data_all_num = []
csv_data_y_avg = {}
with open(train_file_path[0], 'r') as f:
    reader = csv.reader(f)
    for row in reader:
        csv_data.append(row)
csv_data_x = csv_data[0]
for index in range(1, len(csv_data)):
    for zeus in range(len(csv_data[index])):
        if csv_data_x[zeus] == 'is_cheat':
            continue
        if csv_data_x[zeus] in csv_data_y_avg.keys():
            csv_data_y_avg[csv_data_x[zeus]] = float(
                csv_data_y_avg[csv_data_x[zeus]]) + float(csv_data[index][zeus])

        else:
            csv_data_y_avg[csv_data_x[zeus]] = float(csv_data[index][zeus])
for key in csv_data_y_avg:
    csv_data_y_avg[key] = float(csv_data_y_avg[key]) / float(len(csv_data) - 1)

print(csv_data_y_avg)


def get_dataset(file_path):
    dataset = tf.data.experimental.make_csv_dataset(
        file_path,
        batch_size=32,
        label_name=LABEL_COLUMN,
        na_value="?",
        num_epochs=1,
        ignore_errors=True)
    return dataset


def process_continuous_data(mean, data):
    # 标准化数据
    data = tf.cast(data, tf.float32) * 1/(2*mean)
    return tf.reshape(data, [-1, 1])


raw_train_data = get_dataset(train_file_path)
raw_test_data = get_dataset(test_file_path)
examples, labels = next(iter(raw_train_data))  # 第一个批次
print("EXAMPLES: \n", examples, "\n")
print("LABELS: \n", labels)

numerical_columns = []
for feature in csv_data_y_avg.keys():
    num_col = tf.feature_column.numeric_column(
        feature, normalizer_fn=functools.partial(process_continuous_data, csv_data_y_avg[feature]))
    numerical_columns.append(num_col)

preprocessing_layer = tf.keras.layers.DenseFeatures(numerical_columns)
model = tf.keras.Sequential([
    preprocessing_layer,
    tf.keras.layers.Dense(128, activation='relu'),
    tf.keras.layers.Dense(128, activation='relu'),
    tf.keras.layers.Dense(1, activation='sigmoid'),
])

model_name = "anti_aimbot-{}".format(int(time.time()))
TensorBoardcallback = TensorBoard(
    log_dir='logs/{}'.format(model_name),
    histogram_freq=1, batch_size=32,
    write_graph=True, write_grads=False, write_images=True,
    embeddings_freq=0, embeddings_layer_names=None,
    embeddings_metadata=None, embeddings_data=None, update_freq=500
)

model.compile(
    loss='binary_crossentropy',
    optimizer='adam',
    metrics=['accuracy'])
train_data = raw_train_data.shuffle(1500)
test_data = raw_test_data
history = model.fit(train_data, epochs=85, callbacks=[TensorBoardcallback])
test_loss, test_accuracy = model.evaluate(test_data)
predict_data = model.predict(test_data)
print('anti-aimbot: \n\nTest Loss {}, Test Accuracy {}'.format(test_loss, test_accuracy))
for pre, result in zip(predict_data[:20], list(test_data)[0][1][:20]):
    print("player is aimbot :{:5.2f}% ".format(
        100 * pre[0]), " is cheat: ", ("yes" if bool(result) else "no"))
model.save_weights('./save/model_weight')
