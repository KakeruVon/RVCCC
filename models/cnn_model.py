import torch
import torch.nn as nn
import torch.nn.functional as F

class SimpleCNN(nn.Module):
    def __init__(self):
        super(SimpleCNN, self).__init__()
        # 卷积层1: 输入1通道, 输出1通道, 卷积核3x3
        self.conv1 = nn.Conv2d(1, 1, kernel_size=3, padding=0)
        # 卷积层2: 输入1通道, 输出1通道, 卷积核3x3
        self.conv2 = nn.Conv2d(1, 1, kernel_size=3, padding=0)
        # 全连接层: 输入36, 输出10
        self.fc = nn.Linear(36, 10)

    def forward(self, x):
        # 输入x形状: [batch, 1, 32, 32]
        x = F.relu(self.conv1(x))          # 卷积1 + ReLU, 输出: [batch, 1, 30, 30]
        x = F.max_pool2d(x, 2)             # 池化1, 输出: [batch, 1, 15, 15]
        x = F.relu(self.conv2(x))          # 卷积2 + ReLU, 输出: [batch, 1, 13, 13]
        x = F.max_pool2d(x, 2)             # 池化2, 输出: [batch, 1, 6, 6]
        x = x.view(x.size(0), -1)          # 展平, 输出: [batch, 36]
        x = self.fc(x)                     # 全连接, 输出: [batch, 10]
        return x